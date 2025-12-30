# SSE Chunked Pattern Matching

Research notes on HTTP proxies that support streaming SSE with content replacement capabilities, including handling partial matches at chunk boundaries.

## Problem Statement

The challenge is doing pattern matching/replacement on streaming data where pattern boundaries might span chunk boundaries.

This is a classic streaming pattern matching problem. The requirements are:

1. HTTP proxy that supports SSE passthrough
2. Buffering mechanism for content replacement
3. Handling partial matches at chunk boundaries (this is the tricky part)

For the algorithmic side, this is essentially streaming string matching with replacement. The key algorithms here are:

1. **Aho-Corasick** - Great for multiple pattern matching in streaming contexts, maintains state across chunks
2. **KMP (Knuth-Morris-Pratt)** - Single pattern, but the failure function allows you to know exactly how much to buffer
3. **Rabin-Karp** - Rolling hash approach, good for streaming

For the partial match buffering problem specifically:

- You need to buffer at most `max_pattern_length - 1` bytes at chunk boundaries
- When a chunk ends with a partial match, you keep those bytes and prepend them to the next chunk
- The "failure function" in KMP or the state machine in Aho-Corasick naturally handles this

For proxies:

1. **mitmproxy** - Python, very flexible, has streaming support but you'd need to implement the buffering logic
2. **nginx** with sub_filter - But this is more for static content, not great for streaming
3. **Envoy** - Has buffer filters but complex
4. **Custom solutions** using libraries like `httptools` or `h11` in Python

For Zig, you could build something with std.http or use libraries like `zap` or `httpz`.

The streaming replacement with partial matching is often called "streaming search and replace" or "incremental pattern matching." The key insight is that you need to maintain state between chunks.

This is a well-studied problem in streaming text processing:

## The Core Algorithm Problem

What you're describing is **streaming pattern matching with replacement**, where the challenge is handling patterns that straddle chunk boundaries. The classic solutions:

**Aho-Corasick with Buffering**

- Maintains a state machine that naturally tracks partial matches
- When you hit end-of-chunk in a non-root state, you know you have a potential partial match
- Buffer size needed: `max_pattern_length - 1` bytes

**KMP Failure Function Approach**

- For single patterns, the failure function tells you exactly how many bytes at the end of a chunk could be a prefix of your pattern
- You carry forward only those bytes to prepend to the next chunk

The general strategy:

```
on_chunk(data):
    data = pending_buffer + data
    
    # Find all complete matches, replace them
    # But stop processing at (len(data) - max_pattern_len + 1)
    # to avoid splitting a potential match
    
    safe_boundary = len(data) - max_pattern_len + 1
    output = process_and_replace(data[:safe_boundary])
    pending_buffer = data[safe_boundary:]
    
    emit(output)
```

## Existing Proxies/Tools

**mitmproxy** - Python, has `response.stream()` hooks but you'd implement the buffering yourself. Most flexible option.

**OpenResty/nginx** - `ngx_http_sub_module` does replacement but doesn't handle streaming SSE well, and `sub_filter` won't work across chunk boundaries by default.

**Envoy** - Has `envoy.filters.http.buffer` and transformation filters, but configuration is painful for this use case.

**littleproxy** (Java) - Has content filtering support with buffering.

Honestly, for SSE specifically, most proxies punt on this because SSE is inherently streaming and buffering defeats the purpose. You might need to roll your own.

## For a Custom Solution

In Python, `mitmproxy` + a streaming Aho-Corasick implementation (like `ahocorasick` or `pyahocorasick`) would work. In Zig, you'd build it on top of `std.http.Server` with a custom `Aho-Corasick` or rolling buffer.

## Vectorscan/Hyperscan Streaming

Hyperscan/Vectorscan's streaming mode is designed for exactly this problem - it's how Snort3 and Suricata handle reassembled TCP streams.

## Hyperscan Streaming Architecture

The key insight: Hyperscan maintains an opaque **stream state** (`hs_stream_t`) that captures the DFA state(s) across chunk boundaries. You don't manually buffer - the engine tracks partial matches internally.

```
hs_open_stream()     → allocates stream state
hs_scan_stream()     → feed chunks, get match callbacks, state persists
hs_close_stream()    → final matches + cleanup
```

The stream state size depends on your pattern database - you can query it with `hs_stream_size()`. For complex rulesets this can be several KB per stream.

## How It Actually Works

Hyperscan compiles patterns into NFAs, then converts to DFAs (or keeps as NFA for complex patterns). The stream state stores:

1. **Active DFA states** - which states the automaton is currently in
2. **Repeat context** - for patterns with bounded repeats `{n,m}`
3. **Start-of-match tracking** - if you enabled `HS_FLAG_SOM_LEFTMOST`

When you call `hs_scan_stream()` with a new chunk, it resumes from the stored states. Matches that complete mid-chunk fire the callback with the absolute offset from stream start.

## The Catch for Replacement

Hyperscan is **match-only** - it tells you *where* matches are but doesn't do replacement. For content rewriting you need to:

1. Buffer your own output stream
2. Track match start positions (need `HS_FLAG_SOM_LEFTMOST`)
3. On match callback: note the `(start, end)` span
4. When emitting: skip/replace matched regions

The tricky part: matches report at **end** position, so you need SOM to know where to start the replacement. And you must buffer at least until you're sure no match could start in already-seen data.

## Practical Pattern for Proxy Replacement

```
struct StreamRewriter {
    stream: hs_stream_t,
    pending: Buffer,          // data not yet safe to emit
    pending_offset: u64,      // absolute offset of pending[0]
    matches: PriorityQueue,   // matches sorted by start position
    
    fn feed(chunk: []u8) ![]u8 {
        // scan, callbacks populate self.matches
        hs_scan_stream(stream, chunk, chunk.len, ...);
        
        // emit everything before earliest possible match start
        // (depends on your max pattern length or use scratch's 
        // stream state to know active states)
    }
}
```

The `hs_reset_and_copy_stream()` API is also useful if you need to checkpoint/rollback state.

The buffering strategy differs depending on whether you need inline content filtering (blocking on match decisions) or just detection/logging.

## Online Content Replacement

For online content replacement, you need to:

1. Know match boundaries (start and end) before emitting
2. Buffer enough to handle the replacement
3. Maintain low latency for SSE streaming

The fundamental problem: Hyperscan reports matches at the END of the match. Even with SOM (start-of-match), you get the callback when the match completes. But for replacement, you need to:

- Not emit the original matched content
- Emit the replacement instead

The latency/buffering tradeoff is tricky. You can't emit byte N until you're sure no match will START at or before byte N.

With SOM enabled, when you get a match callback at end position E with start S, you know the match spans [S, E). But what about matches that haven't completed yet?

The key insight: you need to know the maximum "lookbehind" - how far back a match could start from the current scan position. This is related to the longest pattern in your database.

With streaming Hyperscan:

1. You scan chunk by chunk
2. Matches fire as they complete
3. Stream state tracks partial matches across chunks

For safe emission, after scanning up to absolute offset O, you can safely emit bytes [0, O - max_pattern_length) because any match starting there would have already completed.

But that's conservative. Hyperscan actually knows more - it knows which states are active and thus which potential matches are "in flight". But this isn't exposed through the API directly.

The practical approach:

- Buffer at least max_pattern_length bytes
- Collect matches with their (start, end) spans
- Sort by start position
- Emit non-matched regions, substitute matched regions
- Careful with overlapping matches (need policy: first match wins? longest? all?)

SSE event boundaries could provide an optimization strategy. By understanding that certain patterns won't cross event boundaries, we might create more efficient flushing mechanisms. This could potentially reduce buffering requirements and improve overall streaming performance, especially in scenarios with well-defined event structures.

The design needs to carefully balance between maintaining match accuracy and minimizing latency, leveraging the unique characteristics of SSE streaming contexts.

That's the harder case. The core tension: you can't emit byte N until you're certain no match will *start* at or before N. Here's the architecture:

## The Buffering Constraint

After scanning up to absolute offset `O`, conservatively safe to emit: `[0, O - max_pattern_len)`

But that adds latency equal to your longest pattern. For SSE where you might be replacing API keys or PII, patterns are typically short (< 100 bytes), so this is usually acceptable.

## Match Ordering Problem

Hyperscan callbacks fire at match *end*, potentially out of start-order. With overlapping patterns you might get:

```
offset 50: match B ends (started at 30)
offset 45: match A ends (started at 40)
```

You need to collect and sort before applying replacements.

## Sketch of the State Machine

zig

```zig
const StreamRewriter = struct {
    stream: *hs_stream_t,
    scratch: *hs_scratch_t,
    
    // Ring buffer holding data not yet safe to emit
    pending: RingBuffer,
    pending_start: u64,  // absolute offset of pending[0]
    
    // Matches awaiting application, sorted by start offset
    matches: std.PriorityQueue(Match, void, orderByStart),
    
    // Longest pattern in DB - determines buffer requirement
    max_pattern_len: usize,
    
    // Replacement table: pattern_id -> replacement bytes
    replacements: []const []const u8,
    
    const Match = struct {
        start: u64,
        end: u64,
        pattern_id: u32,
    };

    pub fn feed(self: *@This(), chunk: []const u8, out: *std.ArrayList(u8)) !void {
        const chunk_end = self.pending_start + self.pending.len + chunk.len;
        
        // Append to pending buffer
        try self.pending.appendSlice(chunk);
        
        // Scan - callbacks populate self.matches via context pointer
        const ret = hs_scan_stream(
            self.stream,
            chunk.ptr,
            @intCast(chunk.len),
            0,
            self.scratch,
            matchCallback,
            @ptrCast(self),
        );
        if (ret != HS_SUCCESS) return error.ScanFailed;
        
        // Safe to emit up to this offset
        const safe_offset = chunk_end -| self.max_pattern_len;
        
        try self.emitUpTo(safe_offset, out);
    }
    
    fn emitUpTo(self: *@This(), offset: u64, out: *std.ArrayList(u8)) !void {
        var cursor = self.pending_start;
        
        while (cursor < offset) {
            // Check if there's a match starting at or before cursor
            if (self.matches.peek()) |m| {
                if (m.start <= cursor) {
                    // Emit everything before match start
                    const pre_len = m.start - cursor;
                    try self.emitPending(pre_len, out);
                    cursor = m.start;
                    
                    // Skip matched content, emit replacement
                    const match = self.matches.remove();
                    self.skipPending(match.end - match.start);
                    try out.appendSlice(self.replacements[match.pattern_id]);
                    cursor = match.end;
                    continue;
                }
            }
            
            // No match blocking us, emit up to offset or next match
            const emit_to = if (self.matches.peek()) |m| @min(offset, m.start) else offset;
            try self.emitPending(emit_to - cursor, out);
            cursor = emit_to;
        }
    }
};
```

## Overlapping Match Policy

You need to decide:

- **First match wins**: Once a region is claimed, skip overlapping matches
- **Longest match**: Buffer all matches for a region, pick longest
- **Priority**: Pattern IDs have precedence

First-match is simplest and usually right for security filtering.

## Flush on Stream End

Don't forget `hs_close_stream()` can report final matches. Then emit remaining buffer with any final replacements.

## SSE-Specific Optimization

If your patterns never cross SSE event boundaries (`\n\n`), you could flush aggressively at those points and reset stream state. But that's fragile if someone crafts input to split sensitive data across events.

Additional areas to explore: match callback wiring, handling the Chimera side for PCRE fallback patterns, or ring buffer mechanics.