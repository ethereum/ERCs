# Bundler Full Sequence Diagram

```plantuml
title UserOperations mempool flow

actor Alice
actor Bob
participant "Bundler RPC"
participant "Ethereum RPC"
participant "UserOp Mempool"

group Alice Submits UserOp
note right of Alice: create UserOp
Alice->"Bundler RPC": ""eth_sendUserOperation""
"Bundler RPC"->"Ethereum RPC": First Validation\ntrace view call to:\n""handleOps([userOpA]"")
"Bundler RPC"->"UserOp Mempool": add ""UserOp"" to mempool
end
|||

group Bob Submits UserOp
note right of Bob: create UserOp
Bob->"Bundler RPC": ""eth_sendUserOperation""
"Bundler RPC"->"Ethereum RPC": First Validation\ntrace view call to\n""handleOps([userOpB]"")
"Bundler RPC"->"UserOp Mempool": add ""UserOp"" to mempool
end
|||

group Build Bundle
    "Bundler RPC"->"UserOp Mempool": fetch pending ""UserOps""
    return ""[UserOpA, UserOpB]""
|||
    loop for each UserOp
        "Bundler RPC"->"Ethereum RPC": Second Validation\ntrace view call to:\n""handleOps([userOp])""
|||
    end

note right of "Bundler RPC": create bundle ""[UserOpA, UserOpB]""
"Bundler RPC"->"Ethereum RPC": Third Validation\ntrace view call to:\n""handleOps([UserOpA, UserOpB])""
|||
"Bundler RPC"->"Ethereum RPC": submit transaction\n""handleOps([UserOpA, UserOpB])""
|||
end
```

# Bundle Sequence Diagram (Without factory)
```plantuml
@startuml
autonumber
participant "EntryPoint" as ep
participant "Account A" as account
participant "Account B" as account2
[->ep++ #gold: ""handleOps(userOps[])"":
group Validations
|||
ep->account++ #blue: <font color=blue> ""validateUserOp""
return ""deposit""
|||
ep->ep: deduct ""Account_A"" deposit
|||
ep->account2++ #green: <font color=green> ""validateUserOp""
return ""deposit""
|||
ep->ep: deduct ""Account_B"" deposit
|||
end

group Executions
|||
ep->account++ #blue: <font color=blue> ""executeUserOp""
deactivate account
ep->ep: refund ""Account_A""
|||
ep->account2++ #green: <font color=green> ""executeUserOp""
deactivate account2
ep->ep: refund ""Account_B""
|||
end
ep-->[: ""compensate(beneficiary)""
hide footbox
```

# Bundle Sequence Diagram (with Paymaster)
```plantuml
@startuml
autonumber
participant "EntryPoint" as ep
participant "Account" as account
participant "Paymaster" as pm
[->ep++ #gold: ""handleOps(userOps[])"":
group Validation
|||
ep->account++ #blue: <font color=blue> ""validateUserOp""
deactivate account
ep->pm++ #gray: ""validatePaymasterUserOp""
deactivate pm
ep->ep: deduct ""Paymaster"" deposit
|||
end
group Execution
|||
ep->account++ #blue: <font color=blue> ""executeUserOp""
    deactivate account
ep->pm++ #gray: ""postOp""
    deactivate pm
ep->ep: refund paymaster
|||
end
ep-->[: ""compensate(beneficiary)""
hide footbox
```

# Bundle Sequence Diagram (with Factory)
```plantuml
@startuml
autonumber
participant "EntryPoint" as ep
participant "Factory" as fact
participant "Account" as account
participant "Account2" as account2
[->ep++ #gold: handleOps(userOps[]):
group Validations
ep->fact++ #gray: create (initCode)
fact->o account: create
return account
ep->account++ #blue: <font color=blue> validateUserOp
return deposit
ep->ep: deduct account deposit
ep->account2++ #green: <font color=green> validateUserOp
return deposit
ep->ep: deduct account2 deposit
end
group Executions
ep->account++ #blue: <font color=blue> exec
deactivate account
ep->ep: refund account1
ep->account2++ #green: <font color=green> exec
deactivate account2
ep->ep: refund account2
end
ep-->[: compensate(beneficiary)
hide footbox
```
