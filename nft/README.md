# Seolint NFT files

The Scan NFT contract's base URI is `https://seolint.xyz/nft/metadata/`, so
tokenURI(tokenId) = `https://seolint.xyz/nft/metadata/<tokenId>.json`.

Each metadata JSON points at its plate image in `nft/images/<tokenId>.jpg`
(the day's globe plate with a ring around that Scan's own node, its number,
kind, tier and claim — the locked plate format).

Files are generated per day after the 12:00 UTC seal from the day's mint
events (seed = keccak(dayId, tokenId, minter): kind = seed % 3 →
Cotton/Wool/Silk; Royal if seed % 1000 >= 970) and uploaded here.
Nothing exists here yet because no Scan has been minted yet.
