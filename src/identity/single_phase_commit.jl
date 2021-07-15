module SinglePhaseCommit

using ..Circo, ..Transactions, ..DistributedIdentities

struct Commit
    transaction::Transaction
end

Transactions.commit!(::Inconsistency, me, writes, service) = begin
    Transactions.apply!(me, writes)
    bulksend(service, me, peers(me), Commit(Transaction(me, writes)))
end

DistributedIdentities.onidmessage(::DistributedIdentities.DistributedIdentityStyle, me, msg::Commit, service) = begin
    # TODO: validate
    Transactions.apply!(me, msg.transaction.writes)
end

end # module