# ROM correctness and performance review

Reviewed commit: `fd0b9c49a92425806968a57243c8a759dbf6005d` on `gooz3-dev`.

This report records nine bug findings and performance targets. It changes no game behavior. The review focused on Rogue gameplay, saves, inventory, queries, adventure generation, palette processing, and trainer setup. It does not establish that every inherited engine path is correct.

## Evidence and limits

- `scripts/build_nix.sh` succeeded.
- `scripts/smoke_test_nix.sh` passed for the debug ROM.
- `scripts/build_nix.sh RELEASE=1` succeeded.
- `scripts/smoke_test_nix.sh` passed for the release ROM.
- AddressSanitizer reproduced a stack-buffer-underflow in the exact `HistoryBufferPush` function extracted into a host C program with a four-element buffer.
- Release ELF inspection confirmed a 73-byte `gRogueQueryBits` and a call to `__divdi3` inside `RGBtoHSV`.
- No targeted gameplay reproduction or performance benchmark was completed. Build and boot success do not verify these gameplay paths.

## Correctness findings

### 1. Safari eviction can write outside save data arrays

Priority: high. Location: [src/rogue_safari.c](../../src/rogue_safari.c), `AllocCustomMonSafariSlot`, lines 422-432.

The eviction loop validates `i`, then accesses randomized `idx` without applying the same checks. When all 16 custom-ID slots are occupied, `idx` can identify a regular or empty entry whose priority matches the lowest custom priority. A zero `customMonLookup` becomes index 255 after subtraction into `u8`. The subsequent write exceeds the 16-element `safariMonCustomIds` array.

Proposed fix: calculate `idx` first and validate that entry before reading its priority or lookup. Preserve the exclusion of `forSafariIndex`.

Validation needed: fill all custom slots, include regular and empty entries with priority zero, vary the random offset, and verify that eviction changes only an eligible custom entry and its ID slot.

### 2. History shifting reads before its buffer

Priority: high. Location: [src/rogue_baked.c](../../src/rogue_baked.c), `HistoryBufferPush`, lines 108-120.

`j = capacity - i - 1` starts the shift at `capacity - 2` and ends by reading `buffer[-1]`. The last entry never changes. Route history, trainer-type history, and wild-encounter history use this function.

For input `[10, 20, 30, 40]`, pushing 99 leaves `[99, 10, 20, 40]` instead of `[99, 10, 20, 30]`, in addition to the invalid read. AddressSanitizer reproduced the invalid read.

Proposed fix: shift with `j = capacity - i` and define safe behavior for capacity zero.

Validation needed: verify ordering for capacities one and four, and run the host reproduction under AddressSanitizer.

### 3. Query iteration reads beyond its bit array

Priority: high. Location: [src/rogue_query.c](../../src/rogue_query.c), `IncrementActiveIteratorInternal`, lines 141-174.

The iterator casts byte storage to `u32*` and loads words before checking bounds. It also compares a word index against a byte count. In the reviewed release ELF, `gRogueQueryBits` is 73 bytes. A word load at byte 72 crosses the allocation, and an empty tail can cause another load at byte 76.

Proposed fix: use aligned, padded storage and check the logical range before each word load. Keep the terminal iterator value outside every valid element range.

Validation needed: empty queries, final valid bits, empty trailing words, and every query type. No player-visible failure was reproduced.

### 4. Adventure generation discards its replacement percentage

Priority: high. Location: [src/rogue_adventurepaths.c](../../src/rogue_adventurepaths.c), line 854.

After calculating 25%, 33%, or 50% replacement, `max(replaceCount, freeRoomCount)` forces at least one replacement attempt per remaining route outside the gauntlet cap. For eight free routes, 25%, and a minimum of two replacements, it attempts eight rather than two. The later minimum-route logic cannot restore routes already replaced.

Proposed fix: cap the count with `min(replaceCount, freeRoomCount)`.

Validation needed: seeded generation across normal, fast-path, and gauntlet modes, including route counts and special-room eligibility at each difficulty.

### 5. IV updates leave cached battle stats stale

Priority: high. Location: [src/rogue_controller.c](../../src/rogue_controller.c), lines 8023, 8426-8467, and 8654.

Hidden Power setup changes IVs after nature setup recalculates stats. Trainer callers do not recalculate afterward. Roamer restoration creates a Pokémon with random IVs, overwrites those IVs, then restores HP using the stale maximum HP. Wild-den generation also boosts an IV without recalculating afterward. `SetMonData` changes IV fields without recalculating cached stats.

Proposed fix: recalculate once after final IV changes. For roamers, recalculate before applying the saved HP percentage.

Validation needed: compare calculated and stored stats for Hidden Power presets, repeated roamer encounters, and wild-den Pokémon. Check current HP handling when maximum HP changes.

### 6. Large inventory pocket sizes wrap

Priority: high, uncommon trigger. Locations: [include/item.h](../../include/item.h), line 51, and [src/item.c](../../src/item.c), line 108.

`BagPocket.capacity` is `u8`, but the bag has 450 slots. The actual pocket length is assigned without a bound. A pocket containing 256 stacks reports zero. Repeated stacks are supported, so distinct item count does not prevent this state. Pocket iteration loses access to entries, and hub inventory snapshots can omit them.

Proposed fix: widen capacity and audit associated loop counters and interfaces. Check whether any persistent layout changes require a save-version bump.

Validation needed: pocket sizes 255, 256, and above, followed by menu access, item removal, hub snapshot, and restoration.

### 7. Hardy presets retain a random nature

Priority: medium. Location: [src/rogue_controller.c](../../src/rogue_controller.c), line 7809.

`if (preset->nature)` skips nature zero, but `NATURE_HARDY` is zero. Existing revised Pelipper and Azumarill profiles use Hardy. Those presets retain the generated nature and its stat modifiers.

Proposed fix: apply the specified nature whenever `skipNature` is false, or introduce a distinct unspecified-nature sentinel if required by the data model.

Validation needed: apply a Hardy preset to a Pokémon with a non-neutral nature and verify its resulting nature and stats.

### 8. Empty hue selection reads before a stack array

Priority: medium. Location: [src/rogue_colour_utils.c](../../src/rogue_colour_utils.c), lines 294-297.

If every reference color is grayscale or sufficiently dark, all colors are exempt and `count` remains zero. The function reads uninitialized `sortedHues[0]` and out-of-bounds `sortedHues[-1]`. A visible failure has not been demonstrated.

Proposed fix: return defined default hues when no colors qualify.

Validation needed: grayscale, black, dark, and mixed reference palettes under a host sanitizer.

### 9. Gameplay time can depend on cosmetic time visuals

Priority: medium, expansion-specific impact identified. Location: [src/rogue_timeofday.c](../../src/rogue_timeofday.c), lines 252-269.

Time getters return cached `timeCode` without recalculating invalid state. Setting time invalidates the cache, but recalculation occurs through palette modification when time visuals are enabled. Disabling those visuals can leave gameplay time stale. Expansion form selection in `rogue_controller.c` uses these getters for Rockruff and Lycanroc filtering.

Proposed fix: recalculate in the getters or maintain gameplay time independently of palette rendering.

Validation needed: cross dawn, day, dusk, and night boundaries with time visuals enabled and disabled. Verify expansion form eligibility.

## Performance targets

These targets have source or binary evidence of avoidable work. Their effect on player-visible latency remains unmeasured.

### Use release builds as the profiling baseline

The Makefile uses `-Og` for debug and `-O2` for release. Profile `scripts/build_nix.sh RELEASE=1` before changing algorithms. Both configurations passed the boot smoke test during this review.

### Reduce palette conversion costs

Location: [src/rogue_colour_utils.c](../../src/rogue_colour_utils.c), `RGBtoHSV` and `Rogue_GenerateLayerPaletteByHue`.

The saturation calculation uses signed 64-bit division even though its numerator is at most 65,025. Release disassembly confirms a `__divdi3` call. The palette path converts the reference palette twice and converts the input again, even when they are the same palette. Layer processing also reconverts values constant within a layer.

Candidate changes: use 32-bit arithmetic, reuse HSV conversions within a palette operation, and evaluate a 32-entry channel conversion lookup. Verify exact output equivalence before measuring custom Pokémon battle and follower palette-load latency. This is load-time work, not established per-frame work.

### Cache trainer sort scores

Location: [src/rogue_trainers.c](../../src/rogue_trainers.c), lines 4058-4061.

Adjacent comparisons repeatedly recalculate both Pokémon scores. A six-member party can require 50 score calculations instead of six. Scoring reads encrypted Pokémon data and scans moves.

Candidate change: calculate scores once and swap them alongside their Pokémon. Use the shrinking sort bound. Verify identical ordering and measure key-trainer party generation latency.

### Preserve memory headroom

The release linker reported 259,772 bytes of EWRAM allocated out of 262,144, leaving 2,372 bytes of static headroom. IWRAM allocation was 25,892 bytes out of 32,768. EWRAM includes the reserved 112 KiB heap, so the static remainder is not the amount available for runtime allocation.

Used release ROM content was 17,147,688 bytes. The output file is padded to 32 MiB. File size alone does not measure runtime performance.

## Suggested implementation order

1. Fix Safari eviction, history shifting, and query bounds.
2. Fix route replacement, cached stats, and inventory capacity.
3. Fix nature, empty palettes, and gameplay time caching.
4. Profile release builds, then evaluate palette and trainer-generation optimizations.

Each gameplay change needs a build, boot smoke test, and targeted mGBA validation. Preserve save compatibility or bump the save version when a persistent layout changes.
