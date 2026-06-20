# Sorted Sets — Redis Reference

Like a Set but every member has a `score` (float). Members are unique; scores can repeat. Members are always sorted by score (ascending). Perfect for leaderboards, priority queues, time-windowed data, and range queries.

**Encoding**: `listpack` (≤128 members AND each ≤64 bytes) → `skiplist + hashtable` (above threshold). Skiplist enables O(log N) range queries.

---

## Quick Reference

| Command | Syntax | Returns | Complexity | Notes |
|---------|--------|---------|-----------|-------|
| ZADD | `ZADD key [NX\|XX] [GT\|LT] [CH] [INCR] score member [score member...]` | added/changed count | O(log N) per element | |
| ZCARD | `ZCARD key` | integer | O(1) | Total member count |
| ZSCORE | `ZSCORE key member` | score / nil | O(1) | |
| ZMSCORE | `ZMSCORE key member [member...]` | array of scores | O(N) | Redis 6.2+ |
| ZINCRBY | `ZINCRBY key delta member` | new score | O(log N) | Creates member at 0 if missing |
| ZRANK | `ZRANK key member [WITHSCORE]` | rank / nil | O(log N) | 0-indexed ascending; WITHSCORE Redis 7.2+ |
| ZREVRANK | `ZREVRANK key member [WITHSCORE]` | rank / nil | O(log N) | 0-indexed descending |
| ZRANGE | `ZRANGE key min max [BYSCORE\|BYLEX] [REV] [LIMIT offset count] [WITHSCORES]` | array | O(log N + M) | Unified command since Redis 6.2 |
| ZRANGEBYSCORE | `ZRANGEBYSCORE key min max [WITHSCORES] [LIMIT offset count]` | array | O(log N + M) | Use ZRANGE BYSCORE instead |
| ZRANGEBYLEX | `ZRANGEBYLEX key min max [LIMIT offset count]` | array | O(log N + M) | Only when all scores equal |
| ZREVRANGE | `ZREVRANGE key start stop [WITHSCORES]` | array | O(log N + M) | Deprecated; use ZRANGE REV |
| ZREVRANGEBYSCORE | `ZREVRANGEBYSCORE key max min [WITHSCORES] [LIMIT offset count]` | array | O(log N + M) | Use ZRANGE BYSCORE REV |
| ZRANGESTORE | `ZRANGESTORE dst src min max [BYSCORE\|BYLEX] [REV] [LIMIT offset count]` | count | O(log N + M) | Redis 6.2+ |
| ZREM | `ZREM key member [member...]` | removed count | O(log N × M) | |
| ZREMRANGEBYSCORE | `ZREMRANGEBYSCORE key min max` | removed count | O(log N + M) | |
| ZREMRANGEBYRANK | `ZREMRANGEBYRANK key start stop` | removed count | O(log N + M) | |
| ZREMRANGEBYLEX | `ZREMRANGEBYLEX key min max` | removed count | O(log N + M) | |
| ZCOUNT | `ZCOUNT key min max` | integer | O(log N) | Count members with score in [min,max] |
| ZLEXCOUNT | `ZLEXCOUNT key min max` | integer | O(log N) | Count by lex range (equal scores) |
| ZPOPMIN | `ZPOPMIN key [count]` | [member,score...] | O(log N × M) | Remove and return lowest-score members |
| ZPOPMAX | `ZPOPMAX key [count]` | [member,score...] | O(log N × M) | Remove and return highest-score members |
| BZPOPMIN | `BZPOPMIN key [key...] timeout` | [key,member,score] | O(log N) | Blocking ZPOPMIN |
| BZPOPMAX | `BZPOPMAX key [key...] timeout` | [key,member,score] | O(log N) | Blocking ZPOPMAX |
| ZRANDMEMBER | `ZRANDMEMBER key [count [WITHSCORES]]` | member(s) | O(N) | Redis 6.2+ |
| ZDIFF | `ZDIFF numkeys key [key...] [WITHSCORES]` | members | O(L + (N-K)log N) | Redis 6.2+ |
| ZDIFFSTORE | `ZDIFFSTORE dst numkeys key [key...]` | count | | |
| ZINTER | `ZINTER numkeys key [key...] [WEIGHTS...] [AGGREGATE SUM\|MIN\|MAX] [WITHSCORES]` | members | O(N×K+M×log M) | |
| ZINTERSTORE | `ZINTERSTORE dst numkeys key [key...] [WEIGHTS...] [AGGREGATE SUM\|MIN\|MAX]` | count | | |
| ZUNION | `ZUNION numkeys key [key...] [WEIGHTS...] [AGGREGATE SUM\|MIN\|MAX] [WITHSCORES]` | members | | |
| ZUNIONSTORE | `ZUNIONSTORE dst numkeys key [key...] [WEIGHTS...] [AGGREGATE SUM\|MIN\|MAX]` | count | | |
| ZSCAN | `ZSCAN key cursor [MATCH pat] [COUNT n]` | [cursor, [member,score...]] | O(1)/call | |

---

## ZADD Flags

```bash
# Scores: any float, including +inf and -inf
ZADD leaderboard 1500 "alice" 2200 "bob" 900 "carol"   # → 3 added

# NX: only add NEW members (don't update existing)
ZADD leaderboard NX 9999 "alice"   # → 0  (alice exists, not updated)
ZADD leaderboard NX 3000 "dave"    # → 1  (dave is new)

# XX: only UPDATE existing members (don't add new)
ZADD leaderboard XX 1800 "alice"   # → 0  (updated alice's score)
ZADD leaderboard XX 5000 "eve"     # → 0  (eve doesn't exist, nothing added)

# GT: only update if new score > current score
ZADD leaderboard GT 500 "alice"    # → 0  (500 < 1800, no change)
ZADD leaderboard GT 2500 "alice"   # → 0  (2500 > 1800, updated)

# LT: only update if new score < current score
ZADD leaderboard LT 100 "bob"      # → 0  (100 < 2200, updated)
ZADD leaderboard LT 9999 "bob"     # → 0  (9999 > 100, no change)

# CH: return count of CHANGED (added+updated) instead of just added
ZADD leaderboard CH 1600 "alice" 500 "new_user"   # → 2 (1 updated + 1 added)

# INCR: use ZADD as ZINCRBY (returns new score)
ZADD leaderboard INCR 100 "alice"  # → "2600.0"  (alice's score + 100)
```

---

## Score Lookup and Ranking

```bash
# Get score
ZSCORE leaderboard "alice"         # → "2600"
ZSCORE leaderboard "nobody"        # → (nil)

# Batch score lookup (Redis 6.2+)
ZMSCORE leaderboard "alice" "bob" "nobody"
# → 1) "2600"  2) "100"  3) (nil)

# Rank (0-indexed, ascending — lowest score = rank 0)
ZRANK leaderboard "alice"          # → 2  (3rd lowest)
ZRANK leaderboard "bob"            # → 0  (lowest score)
ZRANK leaderboard "nobody"         # → (nil)

# Rank with score in one call (Redis 7.2+)
ZRANK leaderboard "alice" WITHSCORE
# → 1) (integer) 2
#    2) "2600"

# Rank descending (highest score = rank 0 — classic leaderboard position)
ZREVRANK leaderboard "alice"       # → 0  (highest scorer)
ZREVRANK leaderboard "bob"         # → 2  (lowest scorer)

# Increment score
ZINCRBY leaderboard 500 "alice"    # → "3100"

# Count total members
ZCARD leaderboard                  # → 4
```

---

## ZRANGE — The Unified Range Command (Redis 6.2+)

```bash
# By index rank (ascending, 0 to end)
ZRANGE leaderboard 0 -1                    # all members, ascending score
ZRANGE leaderboard 0 -1 WITHSCORES        # with scores
ZRANGE leaderboard 0 2                     # first 3 (lowest scores)

# By index rank descending (REV reverses order AND swaps start/stop meaning)
ZRANGE leaderboard 0 -1 REV               # all members, descending score
ZRANGE leaderboard 0 2 REV                # top 3 (highest scores)

# By score range (BYSCORE)
ZRANGE leaderboard 1000 2000 BYSCORE      # scores 1000–2000 (inclusive)
ZRANGE leaderboard "(1000" 2000 BYSCORE   # scores >1000 to 2000 (exclusive min)
ZRANGE leaderboard 1000 "+inf" BYSCORE    # scores >= 1000
ZRANGE leaderboard "-inf" "+inf" BYSCORE  # all (equivalent to index 0 -1)
ZRANGE leaderboard "(1000" "+inf" BYSCORE WITHSCORES LIMIT 0 10  # paginate

# By score descending (REV swaps min/max meaning)
ZRANGE leaderboard "+inf" 1000 BYSCORE REV    # highest to lowest, >= 1000
ZRANGE leaderboard "+inf" "-inf" BYSCORE REV  # all, highest to lowest
```

---

## Priority Queue

```bash
# ZPOPMIN/ZPOPMAX = sorted set as a priority queue
ZADD tasks 1 "urgent_task" 5 "normal_task" 10 "low_priority"

# Process highest priority (lowest score) first
ZPOPMIN tasks          # → 1) "urgent_task"  2) "1"
ZPOPMIN tasks 2        # → pop up to 2 lowest-score members

# Process lowest priority (highest score) first
ZPOPMAX tasks          # → 1) "low_priority"  2) "10"

# Blocking pop (wait for a task to appear)
BZPOPMIN tasks 30      # → 1) "tasks"  2) "normal_task"  3) "5"
# returns nil on timeout
```

---

## Time-Window Range (score = Unix timestamp)

```bash
# Events indexed by timestamp
ZADD events 1717890000 "login:user42"
ZADD events 1717890060 "purchase:order99"
ZADD events 1717890120 "logout:user42"

# Events in last 5 minutes
ZRANGEBYSCORE events (1717889700 +inf        # > now-5min (exclusive lower)
ZRANGEBYSCORE events 1717889700 +inf         # >= now-5min (inclusive lower)

# Count events in time range
ZCOUNT events 1717889700 1717890120          # → 3

# Remove events older than 1 hour
ZREMRANGEBYSCORE events -inf 1717886400

# Sliding window (keep last 1000 events)
ZREMRANGEBYRANK events 0 -1001              # remove oldest if > 1000
```

---

## Leaderboard Pattern

```bash
# Update score
ZINCRBY game:scores 150 "player:42"

# Top 10 players (highest score first, with rank and score)
ZRANGE game:scores 0 9 REV WITHSCORES
# → 1) "player:99"  2) "5200"
#    3) "player:42"  4) "4800"
#    ...

# Player's rank (1-indexed for display)
ZREVRANK game:scores "player:42"            # → 1  (2nd place, 0-indexed)

# Players around me (±2 positions)
ZREVRANK game:scores "player:42"            # → my_rank
ZRANGE game:scores (my_rank-2) (my_rank+2) REV WITHSCORES

# Score needed to reach rank 10
ZRANGE game:scores 9 9 REV WITHSCORES      # score of 10th-place player
```

---

## Lex Range (when all scores are equal)

Use when you want sorted set as an ordered string index (alphabetical).

```bash
ZADD autocomplete 0 "apple" 0 "application" 0 "apply" 0 "apt" 0 "banana"

# All words starting with "app" (lex range: [app to [apq)
ZRANGEBYLEX autocomplete "[app" "[apq"
# → "apple" "application" "apply"

# Prefix search (open-ended: from "app" to "app\xff")
ZRANGEBYLEX autocomplete "[app" "(apq"

# Count matches
ZLEXCOUNT autocomplete "[app" "[apq"        # → 3

# Remove a lex range
ZREMRANGEBYLEX autocomplete "[app" "[apq"
```

---

## Set Operations with Weights

```bash
ZADD team:alice 10 "proj_A" 20 "proj_B"
ZADD team:bob   15 "proj_B" 30 "proj_C"

# Union: combine, sum scores by default
ZUNIONSTORE combined 2 team:alice team:bob
# proj_A: 10, proj_B: 35 (10+15 → bob updated to 35 since both had it), proj_C: 30

# Union with WEIGHTS (multiply scores before aggregation)
ZUNIONSTORE weighted 2 team:alice team:bob WEIGHTS 2 1
# alice's scores × 2, bob's scores × 1

# Intersection: only members in ALL sets
ZINTERSTORE overlap 2 team:alice team:bob AGGREGATE MIN
# proj_B: 15  (minimum of 20 and 15)

# AGGREGATE options: SUM (default), MIN, MAX
```

---

## Gotchas

```
Scores are IEEE 754 doubles — integers up to 2^53 are exact; larger may lose precision
+inf and -inf are valid scores: ZADD key +inf member
Exclusive ranges use '(' prefix: (1000 means >1000 (not >=)
ZRANGE REV also reverses the min/max argument meaning for BYSCORE
ZRANGEBYSCORE min max: min must be <= max (unlike ZRANGE BYSCORE REV where max >= min)
ZRANGEBYLEX only works correctly when all members have the same score
ZINCRBY creates member at score=0 then increments — it doesn't need ZADD first
Lex min/max: use '[' for inclusive, '(' for exclusive, '-' for -inf, '+' for +inf
```

---

→ **See also**: [04-sets.md](04-sets.md) for unordered sets | [03-lists.md](03-lists.md) for simple queues | [10-patterns-recipes.md](10-patterns-recipes.md) for leaderboard and rate-limiter patterns
