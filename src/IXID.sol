// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev The xID precompile address on Epix Chain.
address constant XID_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000900;

/// @dev The xID precompile contract instance.
IXID constant XID = IXID(XID_PRECOMPILE_ADDRESS);

/// @title IXID
/// @notice Interface for the xID precompile on Epix Chain.
///         Only includes methods needed by the tipping contract.
interface IXID {
    /// @notice Resolves an xID name to its owner address.
    /// @param name The name part (e.g., "mud")
    /// @param tld The TLD part (e.g., "epix")
    /// @return owner The owner's EVM address (zero address if not found)
    function resolve(string calldata name, string calldata tld) external view returns (address owner);

    /// @notice Reverse-resolves an address to its primary xID name.
    /// @param addr The EVM address to look up
    /// @return name The name part
    /// @return tld The TLD part
    function reverseResolve(address addr) external view returns (string memory name, string memory tld);

    /// @notice Gets the primary name for an address.
    /// @param owner The EVM address to look up
    /// @return name The name part
    /// @return tld The TLD part
    function getPrimaryName(address owner) external view returns (string memory name, string memory tld);
}
