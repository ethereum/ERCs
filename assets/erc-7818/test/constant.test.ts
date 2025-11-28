// contract name
export const ERC20_EXPIRABLE_CONTRACT = "MockERC20Expirable";

// constructor parameters
export const ERC20_NAME = "PointToken";
export const ERC20_SYMBOL = "POINT";

export const YEAR_IN_MILLISECONDS = 31_556_926_000;

// custom error
export const ERROR_ERC20_INVALID_SENDER = "ERC20InvalidSender";
export const ERROR_ERC20_INVALID_RECEIVER = "ERC20InvalidReceiver";
export const ERROR_ERC20_INSUFFICIENT_BALANCE = "ERC20InsufficientBalance";
export const ERROR_ERC20_INVALID_APPROVER = "ERC20InvalidApprover";
export const ERROR_ERC20_INVALID_SPENDER = "ERC20InvalidSpender";
export const ERROR_ERC20_INSUFFICIENT_ALLOWANCE = "ERC20InsufficientAllowance";
export const ERROR_ERC7818_TRANSFER_EXPIRED = "ERC7818TransferredExpiredToken";
export const ERROR_ERC7818_INVALID_EPOCH = "ERC7818InvalidEpoch";

// events
export const EVENT_TRANSFER = "Transfer";
export const EVENT_APPROVAL = "Approval";

export interface SlidingWindowState {
  initialBlockNumber: Number;
  blocksPerEpoch: Number;
  windowSize: Number;
}
