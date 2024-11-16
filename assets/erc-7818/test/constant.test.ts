export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

// abstracts
export const ERC7818_EXP_BASE_CONTRACT = "MockERC7818";
// export const SLIDING_WINDOW_CONTRACT = "MockSlidingWindow";

export const ERC7818_EXP_EXPIRE_PERIOD = 4;

export const ERC7818_EXP_BLOCK_PERIOD = 400;
export const ERC7818_EXP_FRAME_SIZE = 2;
export const ERC7818_EXP_SLOT_SIZE = 4;
export const ERC20_NAME = "PointToken";
export const ERC20_SYMBOL = "POINT";

export const MINIMUM_SLOT_PER_ERA = 1;
export const MAXIMUM_SLOT_PER_ERA = 12;
export const MINIMUM_FRAME_SIZE = 1;
export const MAXIMUM_FRAME_SIZE = 64;
export const MINIMUM_BLOCK_TIME_IN_MILLISECONDS = 100;
export const MAXIMUM_BLOCK_TIME_IN_MILLISECONDS = 600_000;
export const YEAR_IN_MILLISECONDS = 31_556_926_000;

export const DAY_IN_MILLISECONDS = 86_400_000;

// custom error

export const ERROR_INVALID_BLOCK_TIME = "InvalidBlockTime";
export const ERROR_INVALID_FRAME_SIZE = "InvalidFrameSize";
export const ERROR_INVALID_SLOT_PER_ERA = "InvalidSlotPerEra";

export const ERROR_ERC20_INVALID_SENDER = "ERC20InvalidSender";
export const ERROR_ERC20_INVALID_RECEIVER = "ERC20InvalidReceiver";
export const ERROR_ERC20_INSUFFICIENT_BALANCE = "ERC20InsufficientBalance";
export const ERROR_ERC20_INVALID_APPROVER = "ERC20InvalidApprover";
export const ERROR_ERC20_INVALID_SPENDER = "ERC20InvalidSpender";
export const ERROR_ERC20_INSUFFICIENT_ALLOWANCE = "ERC20InsufficientAllowance";

// events
export const EVENT_TRANSFER = "Transfer";
export const EVENT_APPROVAL = "Approval";

export interface SlidingWindowState {
  _slotSize: Number;
  _blockPerEra: Number;
  _blockPerSlot: Number;
  _frameSizeInBlockLength: Number;
  _frameSizeInEraAndSlotLength: Array<Number>;
  _startBlockNumber: Number;
}
