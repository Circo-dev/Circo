# SPDX-License-Identifier: MPL-2.0
module SinglePhaseCommit

using ..Circo, ..Transactions, ..DistributedIdentities

struct Commit
    transaction::Transaction
end

Transactions.commit!(::Inconsistency, me, writes, service) = begin
    Transactions.apply!(me, writes, service)
    bulksend(service, me, peers(me), Commit(Transaction(me, writes)))
end

DistributedIdentities.onidmessage(::DistributedIdentities.DistributedIdentityStyle, me, msg::Commit, service) = begin
    # TODO: validate
    Transactions.apply!(me, msg.transaction.writes, service)
end

end # module