# Interfaces: Cross-Chain Event Archive

This directory holds the normative interfaces and a reference base contract for the draft ERC
**Cross-Chain Event Archive**. All files here are released under **CC0-1.0**, the same waiver as the
ERC itself (see the repository [`LICENSE.md`](../../LICENSE.md)). They have no external dependencies.

| File                      | Purpose                                                                                |
| ------------------------- | -------------------------------------------------------------------------------------- |
| `IEventArchive.sol`       | Mandatory core: `EventArchived` (with `version`), `isArchived`, `latestVersion`.       |
| `IEventArchiveWriter.sol` | Optional writer extension: `archiveEvent`.                                             |
| `EventArchive.sol`        | Abstract reference base implementing the core with a version-per-`eventId` write path. |

## Reference implementation

`EventArchive.sol` tracks a version per `eventId` and exposes an internal, unguarded `_archiveEvent`.
The first write for an `eventId` records version 1; each subsequent write records the next version, so
corrections reuse the same path. Concrete contracts wrap `_archiveEvent` with their own write path and
authorization model.
