// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

// ---------------------------------------- XML  ------------------------------ */

/**
 * @title XML Representable State interface
 * @notice Contracts implementing this interface expose an XML template that can be rendered
 *         into a canonical XML representation of the contract state at a given block.
 * @dev The XML binding schema and version are defined inside the XML itself (e.g. via
 *      namespaces or attributes). Snapshot consistency is achieved off-chain by evaluating
 *      all view calls against a single fixed block.
 *
 *      In the context of this ERC, a contract that implements this interface and claims
 *      compliance as an "XML-complete" contract MUST ensure that the XML obtained from
 *      this template (together with its bindings) is sufficient to reconstruct the full
 *      contract state that is relevant for off-chain decisions (e.g. valuations,
 *      settlements) at a given block.
 *
 *      Contracts that cannot make an XML-completeness guarantee SHOULD implement only
 *      IXMLRepresentableStatePart (and not this interface) if they wish to expose
 *      partial XML views of their state.
 * @author Christian Fries
 */
interface IXMLRepresentableState {
    /**
     * @notice Returns the XML template string, using a dedicated namespace for bindings.
     * @dev MUST return a well-formed XML 1.0 (or 1.1) document in UTF-8 encoding.
     *      Implementations SHOULD make this string independent of mutable contract state
     *      and environment variables, i.e., effectively constant.
     */
    function stateXmlTemplate() external view returns (string memory);
}

/**
 * @title XML Representable State (partial) interface
 * @notice Optional extension exposing partial XML templates for selected views of the state.
 * @dev The meaning of partId is contract-specific or defined by higher-level standards
 *      (e.g. “settlement context” for ERC-6123).
 *
 *      Implementations of this interface alone are NOT required to be XML-complete:
 *      a contract may expose only partial views of its state without providing a
 *      canonical full XML representation via IXMLRepresentableState.
 */
interface IXMLRepresentableStatePart {
    /**
     * @notice Returns the XML template string for a particular partial state view.
     * @dev MUST return a well-formed XML 1.0 (or 1.1) document in UTF-8 encoding.
     *      Implementations SHOULD make this string independent of mutable contract state
     *      and environment variables, i.e., effectively constant.
     *
     * @param partId Contract-specific identifier of the partial view.
     */
    function statePartXmlTemplate(uint256 partId) external view returns (string memory);
}

// ---------------------------------------- JSON ------------------------------ */

/**
 * @title JSON Representable State interface
 * @notice Contracts implementing this interface expose a JSON template that can be rendered
 *         into a canonical JSON representation of the contract state at a given block.
 * @dev The JSON binding schema and version are out of scope for this ERC. Snapshot consistency
 *      is achieved off-chain by evaluating all view calls against a single fixed block,
 *      analogous to the XML case.
 *
 *      In the context of this ERC, a contract that implements this interface and claims
 *      compliance as a "JSON-complete" contract MUST ensure that the JSON obtained from
 *      this template (together with its bindings) is sufficient to reconstruct the full
 *      contract state that is relevant for off-chain decisions at a given block.
 *
 *      Contracts that cannot make a JSON-completeness guarantee SHOULD implement only
 *      IJSONRepresentableStatePart (and not this interface) if they wish to expose
 *      partial JSON views of their state.
 * @author Christian Fries
 */
interface IJSONRepresentableState {
    /**
     * @notice Returns the JSON template string.
     * @dev MUST return a well-formed JSON document in UTF-8 encoding.
     *      Implementations SHOULD make this string independent of mutable contract state
     *      and environment variables, i.e., effectively constant.
     */
    function stateJsonTemplate() external view returns (string memory);
}

/**
 * @title JSON Representable State (partial) interface
 * @notice Optional extension exposing partial JSON templates for selected views of the state.
 * @dev The meaning of partId is contract-specific or defined by higher-level standards.
 *
 *      Implementations of this interface alone are NOT required to be JSON-complete:
 *      a contract may expose only partial views of its state without providing a
 *      canonical full JSON representation via IJSONRepresentableState.
 */
interface IJSONRepresentableStatePart {
    /**
     * @notice Returns the JSON template string for a particular partial state view.
     * @dev MUST return a well-formed JSON document in UTF-8 encoding.
     *      Implementations SHOULD make this string independent of mutable contract state
     *      and environment variables, i.e., effectively constant.
     *
     * @param partId Contract-specific identifier of the partial view.
     */
    function statePartJsonTemplate(uint256 partId) external view returns (string memory);
}

// ---------------------------------------- State ------------------------------ */

/**
 * @title Representable State (versioned) interface
 * @notice Adds a monotonically increasing version of the representable state.
 *         This optional extension allows off-chain tools to cheaply detect whether
 *         the representation-relevant state has changed.
 * @author Christian Fries
 */
interface IRepresentableStateVersioned {
    /**
     * @notice Monotonically increasing version of the representable state.
     * @dev Implementations SHOULD increment this whenever any mutable state that participates
     *      in the representation changes. It MAY start at 0.
     *
     *      Off-chain tools MAY use this to:
     *        - cache rendered XML/JSON and skip recomputation if the version is unchanged;
     *        - provide a simple ordering of state changes.
     */
    function stateVersion() external view returns (uint256);
}


/**
 * @title Representable State (hashed) interface
 * @notice Exposes a hash of a canonical state tuple used for the representation.
 *         This optional extension allows off-chain tools to verify integrity of an
 *         externally provided representation against on-chain state.
 * @author Christian Fries
 */
interface IRepresentableStateHashed {
    /**
     * @notice Hash of the canonical state tuple used for the representation.
     * @dev Implementations MAY choose their own canonical encoding of state (e.g.,
     *      abi.encode of a tuple of all fields that are represented).
     *
     *      This function is intended for off-chain integrity checks, for example:
     *        - parties can sign (chainId, contract, blockNumber, stateHash);
     *        - renderers can recompute the same hash from the values they used.
     *
     *      It is RECOMMENDED that stateHash() is implemented as a pure/view
     *      function that computes the hash on the fly, instead of storing it in
     *      contract storage and updating it on every change.
     */
    function stateHash() external view returns (bytes32);
}

// ------------------------------ Convenient Aggregations  ------------------------------ */

/**
 * @title XML Representable State (versioned) interface
 * @notice Convenience interface combining XML template and versioned state.
 */
interface IXMLRepresentableStateVersioned is IXMLRepresentableState, IRepresentableStateVersioned {}

/**
 * @title XML Representable State (hashed) interface
 * @notice Convenience interface combining XML template and hashed state.
 */
interface IXMLRepresentableStateHashed is IXMLRepresentableState, IRepresentableStateHashed {}

/**
 * @title XML Representable State (versioned + hashed) convenience interface
 * @notice Convenience interface combining XML template and versioned/hashed state.
 */
interface IXMLRepresentableStateVersionedHashed is IXMLRepresentableState, IRepresentableStateVersioned, IRepresentableStateHashed {}

/**
 * @title JSON Representable State (versioned) interface
 * @notice Optional convenience interface combining JSON template and versioned state.
 */
interface IJSONRepresentableStateVersioned is IJSONRepresentableState, IRepresentableStateVersioned {}

/**
 * @title JSON Representable State (hashed) interface
 * @notice Optional convenience interface combining JSON template and hashed state.
 */
interface IJSONRepresentableStateHashed is IJSONRepresentableState, IRepresentableStateHashed {}

/**
 * @title JSON Representable State (versioned + hashed) convenience interface
 * @notice Optional convenience interface combining JSON template and versioned/hashed state.
 */
interface IJSONRepresentableStateVersionedHashed is IJSONRepresentableState, IRepresentableStateVersioned, IRepresentableStateHashed {}
