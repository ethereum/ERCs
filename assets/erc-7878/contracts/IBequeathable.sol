/// @title EIP-xxxx Bequeathable tokens
/// @dev See https://eips.ethereum.org/EIPS/eip-xxxx

pragma solidity ^0.8.0;

/**
 * @notice Bequeathable interface
 */

interface Bequeathable {

   /**
    * @notice                 The core struct for recording Wills
    * @dev     Will           A struct that keeps track of each owner's Will. One Will per owner
    * @param   executors      An array of addresses that can set an obituary and then subsequently perform the transfer to the inheritor
    * @dev                    It maybe advisable to limit the number of executors for gas efficiency
    * @param   moratoriumTTL  The time that the moratorium must remain in place before the transfer can happen. This is a safety buffer to allow for any other executors to object. We recommend at least a month (60*60*24*30 = 2592000)
    * @param   inheritor      The address that will inherit these tokens, the inheritor is only set at the time of raising the obituary
    * @param   obituaryStart  The time that obituary was announced and moratorium started
    */
   struct Will {
      address[] executors;
      uint256 moratoriumTTL;
      address inheritor;
      uint256 obituaryStart;
   }

   /**
    * @notice              Announce the owner's tokens are to be inherited
    * @dev                 Emitted by `announceObit`
    * @param   owner       The original owner of the tokens
    * @param   inheritor   The address of the wallet that will inherit the tokens once the moratoriumTTL time has passed
    */
   event ObituaryStarted(address indexed owner, address indexed inheritor);

   /** 
    * @notice               Announce the obituary (and moratorium) for the owner has been cancelled, as well as who cancelled it
    * @dev                  Emitted by `cancelObit`
    * @param   owner        The original owner of the tokens
    * @param   cancelledBy  The address that triggered this cancellation. This can be the owner or any of the inheritors
    */
   event ObituaryCancelled(address indexed owner, address indexed cancelledBy);

   /** 
    * @notice                 A token owner can set a Will and names one or more executors who are able to transfer their tokens after their death
    * @dev                    Although more than one executor address can be set, only one is required to start the process and then do the transfer
    * @dev                    Subsequent calls to this function should overwrite any existing Will
    * @param   executors      An array of executors eg legal council, spouse, child 1, child 2 etc..
    * @param   moratoriumTTL  The time that must pass (in seconds) from when the obituary is announced to when the inheritance transfer can take place
    * @dev                    The moratoriumTTL is a safety buffer time frame that allows for any intervention before the tokens get transferred
    */
   function setWill(address[] memory executors, uint256 moratoriumTTL) external;

   /**
    * @notice                  Get the details of a Will if set
    * @dev                     This is a way for the owner to confirm that they have correctly set their Will
    * @param    owner          The current owner of the tokens
    * @return   executors      A list of all the executors for this owners will
    * @return   moratoriumTTL  The length of time (in seconds) that must elapse after calling announceObit before the actual transfer can happen
    */
   function getWill(address owner) external view returns (address[] memory executors, uint256 moratoriumTTL);

   /**
    * @notice              Start the Obituary process, by announcing it and declaring who is the intended inheritor
    * @param   owner       The current owner of the tokens
    * @param   inheritor   The address of the owner to be
    */
   function announceObit(address owner, address inheritor) external;

   /**
    * @notice          Cancel the Obituary that has been previously announced. Can be called by any of the executors (or the owner if still around)
    * @param   owner   The original owner of the tokens
    */
   function cancelObit(address owner) external;

   /**
    * @notice                   Get the designated inheritor and how much time is left before the moratoriumTTL is satisfied
    * @param    owner           The current owner of the tokens
    * @return   inheritor       The named inheritor when the obituary was announced
    * @return   moratoriumTTL   The time left for the moratoriumTTL before the transfer can be done
    * @dev                      A minus figure for moratoriumTTL indicates that the wait time has elapsed and the tokens can be bequeathed
    */
   function getObit(address owner) external view returns (address inheritor, int256 moratoriumTTL);

   /**
    * @notice         Bequeath ie transfer the tokens to the previously declared inheritor
    * @param   owner  The original owner of the tokens
    * @dev            The transfer should happen to the inheritor address when `announceObit` was called
    */
   function bequeath(address owner) external;

}
