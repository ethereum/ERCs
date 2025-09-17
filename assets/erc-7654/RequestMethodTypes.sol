// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0;
import "./Types.sol";
import "./IRequestMethodTypes.sol";
contract RequestMethodTypes is IRequestMethodTypes{
    //@dev Types contains all data types in solidity
    mapping(string => Types.Type[]) methodRequests;
    mapping(string => Types.Type[]) methodResponses;
    mapping(MethodTypes => string[]) methods;
    mapping(string => string) instructions;

    //@dev define the data type of this component
    struct Profiles {
        string name;
        uint256 age;
    }
    mapping(address => Profiles) users;

    constructor() {
        Types.Type[] memory getReqArray = new Types.Type[](1);
        getReqArray[0] = Types.Type.ADDRESS;
        Types.Type[] memory dataTypeArray = new Types.Type[](2);
        dataTypeArray[0] = Types.Type.STRING;
        dataTypeArray[1] = Types.Type.UINT256;
        Types.Type[] memory putReqArray = new Types.Type[](2);
        putReqArray[0] = Types.Type.ADDRESS;
        putReqArray[1] = Types.Type.STRING;
        // @dev initialize get, post, put request parameter data types and response data types
        setMethod(
            "getUser",
            MethodTypes.GET,
            getReqArray,
            dataTypeArray,
            "get user profiles"
        );
        setMethod(
            "createUser",
            MethodTypes.POST,
            dataTypeArray,
            dataTypeArray,
            "Create user profiles"
        );
        setMethod(
            "updateUserName",
            MethodTypes.PUT,
            putReqArray,
            new Types.Type[](0),
            "Update user information"
        );
    }

    function get(string memory _methodName, bytes memory _methodReq)
        public
        view
        returns (bytes memory)
    {
        if (compareStrings(_methodName, "getUser")) {
            address user = abi.decode(_methodReq, (address));
            bytes memory userData = abi.encode(
                users[user].name,
                users[user].age
            );
            return userData;
        } else {
            return abi.encode("");
        }
    }

    function post(string memory _methodName, bytes memory _methodReq)
        public
        payable
        returns (bytes memory)
    {
        if (compareStrings(_methodName, "createUser")) {
            (string memory name, uint256 age) = abi.decode(
                _methodReq,
                (string, uint256)
            );
            users[msg.sender] = Profiles(name, age);
            bytes memory resBytes = abi.encode(name, age);
            emit Response(resBytes);
            return resBytes;
        }
        return abi.encode("");
    }

    function put(string memory _methodName, bytes memory _methodReq)
        public
        payable
        returns (bytes memory)
    {
        if (compareStrings(_methodName, "updateUserName")) {
            (address userAddress, string memory name) = abi.decode(
                _methodReq,
                (address, string)
            );
            require(userAddress == msg.sender);
            users[userAddress].name = name;
        }
        return abi.encode("");
    }

    function options() public pure returns (MethodTypes[] memory) {
        MethodTypes[] memory methodTypes = new MethodTypes[](4);
        methodTypes[0] = MethodTypes.GET;
        methodTypes[1] = MethodTypes.POST;
        methodTypes[2] = MethodTypes.PUT;
        methodTypes[3] = MethodTypes.OPTIONS;
        return methodTypes;
    }

    function setMethod(
        string memory _methodName,
        MethodTypes _methodType,
        Types.Type[] memory _methodReq,
        Types.Type[] memory _methodRes,
        string memory _instruction
    ) private {
        methods[_methodType].push(_methodName);
        methodRequests[_methodName] = _methodReq;
        methodResponses[_methodName] = _methodRes;
        instructions[_methodName] = _instruction;
    }

    function getMethodReqAndRes(string memory _methodName)
        public
        view
        returns (Types.Type[] memory, Types.Type[] memory)
    {
        return (methodRequests[_methodName], methodResponses[_methodName]);
    }

    function getMethods(MethodTypes _methodTypes)
        public
        view
        returns (string[] memory)
    {
        return methods[_methodTypes];
    }

    function getMethodInstruction(string memory _methodName)
        public
        view
        returns (string memory)
    {
        return instructions[_methodName];
    }

    //@dev compares two strings for equality
    function compareStrings(string memory _a, string memory _b)
        private
        pure
        returns (bool)
    {
        return
            keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

}