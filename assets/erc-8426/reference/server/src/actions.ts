import type { Address } from "viem";

import type { AuthorizeTarget } from "./authorize.js";

/// The result of executing a pass-reachable action once it is authorized.
export interface ActionResult {
  action: string;
  tokenId: string;
  account: Address;
  executed: boolean;
}

/// Execute the action.
///
///  This is a stub: authorization is the part of the flow the standard governs,
///  so everything interesting has already happened by the time we get here. A
///  real server would apply the effect (for example call the contract's
///  `levelUp` from a relayer, or record an off-chain change), then emit
///  `PassUpdate` on chain and push the refreshed pass to installed devices. It
///  runs only after `authorize` has returned ok, which is the guarantee that
///  the caller proved control of the owning account and that the account still
///  owns the token as of a fresh read.
export function executeAction(target: AuthorizeTarget, account: Address): ActionResult {
  return {
    action: target.action,
    tokenId: target.tokenId,
    account,
    executed: true,
  };
}
