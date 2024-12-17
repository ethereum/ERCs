# ERC-X: Consolidated Dynamic Storage in Solidity  

## Title: Consolidated Dynamic Storage

**Author(s):** Cameron Warnick  
[cameronwarnicketh@gmail.com](mailto:cameronwarnicketh@gmail.com), [github.com/wisecameron](https://github.com/wisecameron)  

**Status:** Draft  
**Type:** Standards Track  
**Created:** 2024-13-12  
**Requires:** None  
discussions-to: https://ethereum-magicians.org/t/erc-7844-consolidated-dynamic-storage-cds/22217

---

## Abstract  

While Diamond Storage and Proxy-Delegate patterns offer time-tested upgradeability solutions, they introduce clear constraints: bloated contract structures, rigid storage alignment requirements, and complex integrations for new logic that become increasingly cumbersome as project scope expands.  

**Consolidated Dynamic Storage (CDS)** introduces a flexible, gas-efficient system that supports **post-deployment creation and extension** of both **mapped struct layouts** and their corresponding **segregated storage spaces**, enabling seamless storage evolution through a unified, centralized layer shared by linked pure contracts.

CDS achieves this by combining two core features:

- **Extendable Structs**: Struct members can be dynamically appended to existing mapped structures using a compact `[bitCount(128), type(64), size(64)]` format.
- **Modular Storage Spaces**: Configurable, logically-separated namespaces that support dynamic mappings-of-structs and in-place extensions.

This architecture centralizes storage management, enabling seamless storage-level integration for new contracts.  By eliminating slot collisions, streamlining upgrades, and enabling dynamic state transparency, CDS is ideal for evolving systems like **DeFi protocols, DAOs**, and **modular frameworks** requiring frequent upgrades.

---

## Motivation  

![Scaling CDS](https://github.com/wisecameron/ConsolidatedDynamicStorage/blob/main/images/Scaling%20CDS.png)

The Ethereum ecosystem relies heavily on upgradeable smart contract patterns to enable flexibility in evolving protocols and systems. Contemporary solutions such as **Proxy-Delegate** patterns and the **Diamond Standard (ERC-2535)** have proven their utility but suffer from significant limitations:

1. **Rigid Storage Layouts**:
    - Proxy-based models and the Diamond Standard require **predefined storage layouts**. Developers must "reserve space" for potential future fields, which complicates upgrades and wastes storage.
    
	    **Example**: In a DAO framework managing a dynamic treasury, adding a new struct member (e.g., `lastClaimedReward`) to an existing `mapping(address => UserInfo)` would require redefining the contract logic or migrating state—both cumbersome processes.
    
2. **Storage Collision Risks**:
    - Manually managing storage slots in proxy models or Diamond facets risks **overlapping storage slots**, leading to corruption of critical state data. This requires extreme diligence during development and audits.
    
3.  **Structural Inefficiency**:
    - Proxy-delegate models require a one-to-one mapping between pure contracts and their storage, creating a *spiderweb pattern* of linked contracts.  This introduces higher gas costs and added complexity.  Additionally, cross-contract calls introduce clear convolution: for instance, a single cross-contract call would invoke: ProxyA, DelegateA, ProxyB, DelegateB.  Diamonds can introduce similar convolution: while routing calls through diamonds introduces a consistent entry point, it also creates a bottleneck for growing systems.  As more diamonds are introduced, a similar spiderweb pattern takes shape emerge.
    
![Scaling Proxy Delegate](https://github.com/wisecameron/ConsolidatedDynamicStorage/blob/main/images/Scaling%20Proxy%20Delegate.png)
![Scaling Diamonds](https://github.com/wisecameron/ConsolidatedDynamicStorage/blob/main/images/Scaling%20Diamonds.png)
	
4. **Lack of In-Place Solutions**
    - Existing solutions present a clear lack of contract-level control over the storage space.  In the case of proxy-delegate models, an equivalent to *upgradeable structs* is technically achievable, but requires upgrading and swapping out contracts.  For Diamond facets, the situation is more dire, as the storage layout is completely rigid unless paired with a proxy-delegate model.  
    
    - Introducing fine-grained, system-wide control over storage simplifies this process. Developers can dynamically add storage fields through a simple function invocation, reducing complexity and audit costs.  Critically, this functionality does not need to be applied at a blanket level -- basic permission management systems and governance solutions can re-instate spotless decentralization while the capability remains intact.  
      
5. **Complex Integrations** 
	 
	- Integrating legacy contracts with new logic typically requires the re-deployment of *both contracts,* significantly increasing the effort required.  By linking them at the storage layer, we streamline upgrades by reducing unnecessary separation between logic and storage, eliminating the need for dual redeployments.  For example, integrating a new rewards system into an existing contract could easily require redeploying both the rewards logic and the main contract, along with manual state migration. This process adds significant effort and complexity.
	

**Consolidated Dynamic Storage (CDS)** comprehensively addresses these limitations by introducing a **flexible and gas-efficient storage model** that enables post-deployment of expansion and creation of dynamic mapping-of-structs without redeployment. Specifically:

- **Dynamic Structs** allow new fields to be added efficiently in a standardized, collision-free manner.
- Segregated storage spaces synergize with dynamic structs to enable in-place growth *to infinity.*
- Leveraging a single all-encompassing storage layer, and without relying on it as a call router, allows us to minimize the spiderweb pattern to its most innocuous form.  
- While centralization of the storage layer seems risky on the surface level, it is actually a responsible approach: with CDS, the potential for data issues is limited to the scope a single contract.  Additionally, simple permissions systems can effectively block all direct access by non-autonomous agents, leaving the burden of risk solely on the connected pure contracts.
- **Collision-Free Storage** ensures logical separation of storage spaces via hashed namespaces and configurable offsets.
- **Optional Batch Operations** significantly reduce gas costs for high-throughput systems by minimizing external calls.
- **State Transparency** provides query functions that allow developers to dynamically inspect storage layouts and interact with stored data.

By solving these limitations, CDS simplifies upgradeability, reduces gas costs, and eliminates storage layout constraints, empowering developers to build evolving systems like DeFi protocols, modular frameworks, and DAOs with greater flexibility and confidence.

![Adaptability](https://github.com/wisecameron/ConsolidatedDynamicStorage/blob/main/images/Adaptability.png)

---

## Specification  

### Extendable Structs and Storage Spaces

- Extendable structs leverage dynamic mappings with deterministic field hashes (`keccak256`).  
- The base struct remains immutable, while fields can be dynamically appended.
- Storage spaces equate to a simple extension of the hashing structure, segmenting both struct-defining and active data.

Each struct member is defined using compact metadata:

| **Field**  | **Bits** | **Description**                          |
| ---------- | -------- | ---------------------------------------- |
| `bitCount` | 128      | Starting bit offset for the member.      |
| `size`     | 64       | Size of the member in bits.              |
| `type`     | 64       | Type ID (e.g., `uint256`, `bool`, etc.). |

**Type IDs**:

| **Type**                   | **ID** | **Size**     |
| -------------------------- | ------ | ------------ |
| `uint`                     | 1      | 8...256 bits |
| `int`                      | 2      | 8...256 bits |
| `bool`                     | 3      | 8 bits       |
| `address`                  | 4      | 160 bits     |
| `bytes32 (optional)`       | 5      | 256 bits     |
| `string (≡ bytes)`         | 6      | Dynamic      |

*For arrays, developers can define unpacking logic to treat `string` or `bytes` fields as indexed collections of dynamic elements.*

**Example Hash Structure**:

There are three main segments that require separate hashing structures to resolve any potential for collisions, meta-segmented by their particular storage spaces.  These are: storage space state data and member-specific data, storage space live data, and storage space dynamic data. 

There are two special values that are required: a `safeIndex` and a `stringIndex`.  Both are expounded upon in detail below.

It is recommended to leverage a unique hash offset for each space, as this simplifies the development and audit process considerably, and thereby reduces the risk of improper implementation.

Another key point is the necessity of a storageSpace `offset` value.  This will be marked explicitly in the section below for the sake of clarity.

Storage Space State Data:
`mstore(0x0, offset: shl(176, mul(storageSpaces, MEMBERS_LIM))))`
`keccak256(0x0, 0xA)` -> {`members(64), entries(64), stringIndex(64), safeIndex (64)`}

Storage Space Member-Specific Data:
`mstore(0x0, shl(168, add(offset: mul(storageSpaces, add(1, MEMBERS_LIM)), entryIndex)))`
`keccak256(0x0, 0xB)` -> {`bitCount(128), size(64), type(64)`}
*String*: `keccak256(0x0, 0xB)` -> {`stringIndex(128), type(128)`}

Storage Space Live Data:
`mstore(0x0, shl(160,  add(entryIndex, mul(5 billion, storageSpace))))`
`keccak256(0x0, 0xC)` -> {`packed slot`}

Storage Space Dynamic Data:
`[strindex][entryIndex][storageSpace]`
```solidity
        mstore(
            0x0,
            or(
                or(shl(224, entryStrindex), shl(192, entryIndex)),
                shl(176, and(storageSpace, 0xFFFF))
            )
        )
        keccak256(0x0, 0xB)
```

stringIndex, safeIndex:
String index is used to properly separate strings.  Since strings have a dynamic size, they do not use `bitCount`.  Hence, we can fill their `bitCount` with `stringIndex` instead in member data.

However, this raises a problem when implementing extendable structs: *if the last member is a string, we might reference back to it, tricking the system into believing the `stringIndex` is a `bitCount`.* Hence, we leverage `safeIndex`, which simply records the most recent valid index we can use to derive `bitCount`.  Critically, if `safeIndex` is zero, we are still safe from complications, because a zero `strindex` doubles as a valid `bitCount` in that instance.

Example Implementation:
```solidity
function insert_new_member(
	uint256 valType,
	uint256 valSize,
	uint256 storageSpace
) external
{
	verify type and size
	retrieve memberData
	
	if(type not string)
	{
		get safeIndex
		assign bitCount := prev bitCount + sizeof previous
		verify size
		get storage page
		verify we will not overflow
		if overflow, push to next page (update bitCount to head of next page)
		pack memberData
		store memberData
		update safeIndex, members in state data for storage space
	}
	if(type is string)
	{
		get stringIndex
		pack with type
		store packed metadata in memberData
		increment stringIndex, members
		store updated state data for storage sapce
	}

}
```

## Initialization

![Basic Interaction Flow](https://github.com/wisecameron/ConsolidatedDynamicStorage/blob/main/images/Basic_interaction_flow_CDS.png)
![CDS Init, Extension](https://github.com/wisecameron/ConsolidatedDynamicStorage/blob/main/images/CDS%20Init,%20Extension.png)
Getting a finished system up and running is straightforward.  The `init_create` function handles storage space creation in both an initialization and live extension setting.  The function takes an array of types and sizes, which must conform to the above specifications, and be equivalent in length.

```solidity
function init_create(
	uint256[] memory types,
	uint256[] memory sizes,
)
{
	for(i in range sizes)
	{
		if(types[i] in [1..5])
		{
			validate size given type
			calculate bitCount for new entry
			pack {bitCount, types, sizes}
			store the packed value in the member data of the storage space
			bitCount := bitCount + size
			increase safeIndex
		}
		if(types[i] is 6)
		{
			create packed value {stringIndex, 6}
			store the packed value in the member data of the storage space
			increment stringIndex
		}
	}
	pack storage space data: {members, entries, stringIndex, safeIndex}
	store storage space data
	storageSpaces += 1
}
```
## Interface

```solidity
    function init_create(
	    uint256[] memory types, 
	    uint256[] memory sizes
	) external;

    function insert_new_member(
	    uint256 valType, 
	    uint256 size, 
	    uint256 storageSpace
	) external;

	function push(
		uint256 storageSpace
	) external;

    function pushMany(
	    uint256 amount, 
	    uint256 storageSpace
	) external;

    function put(
	    uint256 data, 
	    uint256 memberIndex, 
	    uint256 entryIndex, 
	    uint256 storageSpace
	) external;

	function put_string(
		string memory data, 
		uint256 memberIndex, 
		uint256 entryIndex, 
		uint256 storageSpace
	) external;

	
   (optional) function put_batch(
	   uint256[] memory values, 
	   uint256[] memory members, 
	   uint256 entryIndex, 
	   uint256 storageSpace
	) external;

    function get(
	    uint256 memberIndex, 
	    uint256 entryIndex, 
	    uint256 storageSpace
	) external view returns(uint256);

    function get_string(
	    uint256 memberIndex, 
	    uint256 entryIndex, 
	    uint256 storageSpace
	) external view returns(string memory returnValue);

    (optional) function get_batch(
	    uint256[] memory members, 
	    uint256 entryIndex, 
	    uint256 storageSpace
	) external view returns(uint256[] memory result);

    function get_storage_space_state_data(
	    uint256 storageSpace
	) external view returns(
		uint256 members, 
		uint256 entries,
		uint256 stringIndex,
		uint256 safeIndex
	);
	
    function total_members(
	    uint256 storageSpace
	) external view returns(uint256);

	/**
	* For string, bitCount->stringIndex, size param is extraneous.
	/*
	function get_member_data(
		uint256 memberIndex,
		uint256 storageSpace
	) external view returns(
		uint256 bitCount, 
		uint256 valSize,
		uint256 valType, 
	)
```

---

## Rationale  

**Undeniably Radical** Consolidated Dynamic Storage (CDS) is clearly a complex solution—but complexity does not preclude utility: in this case, it is a necessary tradeoff.  For high-performance and cutting-edge systems, CDS solves **real, tangible problems** that contemporary upgradeability solutions cannot address in equal stride:

- **In-Place Storage Growth**: CDS introduces two-tiered extendable storage, eliminating the need for migrations or pre-reserved slots.  This dramatically simplifies upgrades and reduces gas costs.
- **Streamlined Development and Audits**: While CDS demands rigorous upfront effort, its benefits compound post-deployment by minimizing changes, reducing audit overhead, and mitigating upgrade vulnerabilities.
- **Proven Feasibility**: Working, robust models of CDS already exist.  The EVM’s mature auditing ecosystem ensures that well-designed implementations can be secure and reliable.
- **Launchpad for Plug-and-Play Infra Solutions**  CDS’s centralized storage layer, paired with its low-level access, forms a robust foundation for further system-level enhancements.  Frameworks like [HoneyBadger](https://honeybadgerframework.com) demonstrate CDS’s real-world feasibility, leveraging its flexibility to implement permission management, highly-optimized storage operations, native governance, and modular support.

In short, CDS trades initial complexity for **long-term efficiency, safety, and flexibility**—a tradeoff that is more than justified for systems requiring cutting-edge upgradeability. As audited, plug-and-play implementations become available, CDS will become an **accessible and powerful tool** for developers building systems that demand efficiency and capabilities beyond what is currently accessible.

### **Why Not Diamond Storage?**

The **Diamond Standard (ERC-2535)** modularizes smart contract logic elegantly, but retains a rigid storage model. While facets can be upgraded post-deployment, **the storage layout itself remains static**. To mirror the capabilities of CDS, the Diamond storage layer would require its own proxy-delegate solution up-front.  Developers would need to swap the diamond delegate, then re-connect all of its linked contracts.  *In a production environment, this process represents both cost and risk.*  

---

## Backwards Compatibility  

This ERC introduces a new design pattern and does not interfere with existing Solidity implementations.  CDS *does* *not* implicitly interfere with common libraries such as those provided by OpenZeppelin, but is not supported explicitly. Library-imposed global data within linked contracts leveraging 

---

## **Test Cases**

### **1. Core Functionality**

- **Initialization**
    - Input: `types = [1, 3, 6], sizes = [32, 8, 128]`.
    - Expected: Storage space initialized with 3 members.
- **Insert New Members**
    - Input: `insert_new_member(1, 128, storageSpace = 0)`.
    - Expected: New `uint128` member added with correct `bitCount`.
- **Data Storage and Retrieval**
    - Input: `put(42, memberIndex = 0, entryIndex = 0, storageSpace = 0)` → `get(0, 0, 0)`.
    - Expected: `42`.

### **2. Edge Cases**

- **String Handling**
    - Input: Insert five strings consecutively.
    - Expected: No collisions; strings retrieved accurately.
    
    - Input: insert two dynamic strings, then one uint256
    - Expected: uint256 is properly configured with:
		    `bitCount == 0` 
		because: 
		    `safeIndex == 0` maps to the dynamic string with index 0.  This zero value fills both decoded `{type, size}` slots in the standard type construction logic.  Hence, we begin with a valid bitCount of 0.
		    
- **Entry Creation**
    - Input: Add 10,000 entries to a storage space with `pushMany`.
    - Expected: System can store to  any of these entry indices.
    
- **Invalid Input**
    - Input: `put(42, memberIndex = 1, storageSpace = 0)`.
    - Expected: Reverts with error.
    
	* Input: `put("42", memberIndex = 1, entryIndex = 0, storageSpace = 0)`.
    - Expected: Reverts with error.
    
	- Input: `put_string(42, memberIndex = 1, entryIndex = 0, storageSpace = 0)`.
    - Expected: Reverts with error.

## Gas Benchmarks (HoneyBadger)

* This section assumes that storage operations interact with pre-populated slots.
* Displayed values reference *execution* cost.

	`init_create([1], [256]):` 93,860 gas
	`init_create([1,1,1], [8,256,256]):` 140,024 gas
	`insert_new_member:` 40,653 gas
	`push:` 10,316 gas
	`put:` 15,543 gas
	`put_batch([20, 20], [0, 1], 0, 0):` 22,895 gas
	`get`: 9374 gas

---

## Implementation

Refer to [CDS Minimal Example](https://github.com/wisecameron/ConsolidatedDynamicStorage/blob/main/contracts/CDSMinimal.sol)
