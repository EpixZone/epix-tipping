# Epix Tipping

Tipping smart contract for [Epix Chain](https://epix.zone). Users tip content creators with native EPIX, with on-chain stats for UI rendering. Demonstrates how to integrate the **xID precompile** into Solidity contracts.

## xID Integration

Epix Chain provides an [xID precompile](https://docs.epix.zone) at `0x0000000000000000000000000000000000000900` that lets smart contracts resolve human-readable names to EVM addresses (and vice versa) without any external oracle or off-chain lookup.

### Interface

Copy `src/IXID.sol` into your project to use the xID precompile:

```solidity
address constant XID_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000900;
IXID constant XID = IXID(XID_PRECOMPILE_ADDRESS);

interface IXID {
    // "mud" + "epix" -> 0x1234...
    function resolve(string calldata name, string calldata tld) external view returns (address owner);

    // 0x1234... -> ("mud", "epix")
    function reverseResolve(address addr) external view returns (string memory name, string memory tld);

    // Same as reverseResolve but returns the user's chosen primary name
    function getPrimaryName(address owner) external view returns (string memory name, string memory tld);
}
```

### Forward Resolution (name to address)

Resolve an xID name to an EVM address. This contract uses it to let users tip by name instead of address:

```solidity
function tipByXid(bytes32 contentHash, string calldata name, string calldata tld) external payable {
    address resolved = _tryResolve(name, tld);
    require(resolved != address(0), "xID: name not found");
    _tip(contentHash, resolved);
}

function _tryResolve(string calldata name, string calldata tld) private view returns (address) {
    try XID.resolve(name, tld) returns (address owner) {
        return owner;
    } catch {
        return address(0);  // precompile unavailable or name not found
    }
}
```

### Reverse Resolution (address to name)

Look up the xID name for an address. This contract uses it to display tipper names in leaderboards:

```solidity
function _tryReverseResolve(address addr) private view returns (string memory name, string memory tld) {
    try XID.reverseResolve(addr) returns (string memory n, string memory t) {
        return (n, t);
    } catch {
        return ("", "");  // no xID registered
    }
}
```

### Best Practice: Always Wrap in try/catch

The xID precompile is a chain-level feature. If your contract might be deployed on a fork, testnet, or chain where the precompile isn't available, wrap calls in `try/catch` to prevent reverts from bricking your contract.

## How It Works

Each piece of content (forum post, blog entry, social post) is identified by a `bytes32` content hash:

```
contentHash = keccak256(abi.encode(siteAddress, authorDirectory, postId))
```

The first tip to a content hash permanently registers the creator address. Subsequent tips are forwarded directly to the creator. 100% of every tip goes to the creator - no fees, no admin, no pause.

### Stats Tracking

The contract tracks stats on-chain for UI rendering (all free to read via `eth_call`):

- **Summary** - creator address, total EPIX tipped, unique tipper count (2 storage slots)
- **Top 3** - highest cumulative tippers with amounts and xID names
- **Last 3** - most recent tips with timestamps and xID names

## Usage

```solidity
// Tip by direct address
tipping.tip{value: 1 ether}(contentHash, creatorAddress);

// Tip by xID name (resolves on-chain)
tipping.tipByXid{value: 1 ether}(contentHash, "mud", "epix");

// After creator is registered, address(0) uses stored creator
tipping.tip{value: 1 ether}(contentHash, address(0));

// Quick summary for tip button badge (2 slot reads)
(address creator, uint256 totalAmount, uint32 uniqueTippers) =
    tipping.getContentSummary(contentHash);

// Full stats for tip modal
IEpixTipping.ContentInfo memory info = tipping.getContentInfo(contentHash);

// Batch tip counts for page load (1 RPC call instead of N)
uint32[] memory counts = tipping.getTipperCountBatch(contentHashes);
```

## Development

```bash
forge build       # Compile
forge test -vvv   # Run tests
forge fmt         # Format
```

### Deploy

```bash
cp .env.example .env
# Edit .env with your deployer key and RPC URL
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --legacy
```

## Contract Addresses

| Network | Address |
|---------|---------|
| Testnet | `0x22c5622378fb8E9AB52EA0b00cAce94474829df3` |
| Mainnet | TBD |

## License

MIT
