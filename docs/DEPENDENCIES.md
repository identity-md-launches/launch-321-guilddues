# Vendored dependencies

All dependencies are ordinary source files in `lib/`; no submodules, package install, or network are needed to compile or test. Foundry and the pinned Solidity compiler are external build tools.

- OpenZeppelin Contracts **v5.0.2**, MIT: unmodified transitive sources for ERC20, SafeERC20 and ReentrancyGuard, with LICENSE. Source: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2. Download archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`.
- forge-std **v1.9.7**, MIT / Apache-2.0: unmodified `src/` and license files, used only by tests. Source: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7. Download archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.

Only the imported OpenZeppelin subset is included. Production contracts do not import forge-std. Remappings resolve these dependencies locally. The archive digests describe the downloaded archives, not a separate attestation or admission artifact.
