// SPDX-License-Identifier: CC0-1.0
pragma solidity >= 0.8.0;
import "./IMultiplayerOnchainGame.sol";
import "./Types.sol";
contract MOG is IMOG{

    struct Message{
        uint256 roomId;
        bytes content;
        Types.Type[] contentTypes;
        uint256 from;
        uint256[] to;
    }

    uint256 roomIds=0;
    mapping(uint256=>mapping(address=>uint256)) RoomMembers;
    mapping(uint256=>uint256)RoomMemberIds;
    mapping(uint256=>uint256)RoomMessageIds;
    mapping(uint256=>mapping(uint256=>Message)) Messages;
    mapping(uint256=>mapping(address=>bool)) MemberExists;
    mapping(uint256=>mapping(uint256=>uint256[])) MemberMessageIds;
    mapping(address=>uint256[]) MemberRoomIds;
    mapping(uint256=>mapping(uint256=>uint256)) MemberHPs; //The state of room members in the game

    function createRoom() public virtual returns(uint256){
        return roomIds++;
    }

    function getRoomCount()public view returns(uint256){
        return roomIds;
    }

    function hasMember(uint256 _roomId,address _member)public view returns(bool){
        return MemberExists[_roomId][_member];
    }

    function joinRoom(uint256 _roomId) public virtual returns(uint256) {
        require(_roomId<=roomIds);
        require(!MemberExists[_roomId][msg.sender]);
        uint256 memberId=RoomMemberIds[_roomId];
        RoomMembers[_roomId][msg.sender]=memberId;
        RoomMemberIds[_roomId]=RoomMemberIds[_roomId]+1;
        MemberExists[_roomId][msg.sender]=true;
        MemberRoomIds[msg.sender].push(_roomId);

        MemberHPs[_roomId][memberId]=100;
        return memberId;
    }

    function getRoomIds(address _member)public view returns(uint256[] memory){
        return MemberRoomIds[_member];
    }

    function getMemberCount(uint256 _roomId)public view returns(uint256){
        return RoomMemberIds[_roomId];
    }

    function getMemberId(uint256 _roomId,address _member)view public returns(uint256){
        return RoomMembers[_roomId][_member];
    }

    function sendMessage(uint256 _roomId,uint256[] memory _to,bytes memory _message) public virtual returns(uint256){
        require(_roomId<=roomIds);
        require(hasMember( _roomId, msg.sender));
        uint256 from = getMemberId( _roomId, msg.sender);
        uint256 currentRoomMessageId=RoomMessageIds[_roomId];

        (uint256 action,uint256 value)=abi.decode(_message,(uint256,uint256));    
        
        //game logic
        for(uint256 i=0;i<_to.length;i++){
            if(_to[i]<=RoomMemberIds[_roomId]){
                MemberMessageIds[_roomId][_to[i]].push(currentRoomMessageId);
                //attack
                if(action==0){
                    MemberHPs[_roomId][_to[i]]-=value;
                }else{
                //heal    
                    MemberHPs[_roomId][_to[i]]+=value;
                }
            }else{
                revert("Receiver does not exist");
            }   
        }

       Types.Type[] memory messageTypeArray = new Types.Type[](2);
        messageTypeArray[0] = Types.Type.UINT256;
        messageTypeArray[1] = Types.Type.UINT256;
        Messages[_roomId][currentRoomMessageId]=Message(_roomId,_message,messageTypeArray,from,_to);
        RoomMessageIds[_roomId]=currentRoomMessageId+1;
        return currentRoomMessageId;
    }

    function getMessageIds(uint256 _roomId,uint256 _member)view public returns(uint256[] memory){
        return MemberMessageIds[_roomId][_member];
    }

    function getMessage(uint256 _roomId,uint256 _messageId)view public returns(bytes memory,Types.Type[] memory,uint256,uint256[] memory){
        Message memory message=Messages[_roomId][_messageId];
        return (message.content,message.contentTypes,message.from,message.to);
    }

}