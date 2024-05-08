module lottery::pool_manager{
    use std::string::String;
    use lottery::pool::{Self,Pool,PoolTicket};
    public struct PoolAdminCap has key {id:UID}   


    fun create_pool_admin_cap(ctx:&mut TxContext) : PoolAdminCap {
        PoolAdminCap{
            id:object::new(ctx)
        }
    }


    public(package) fun mint_pool_admin_cap_and_take(ctx:&mut TxContext){
        transfer::transfer(create_pool_admin_cap(ctx),tx_context::sender(ctx));
    }

    public(package) fun create_pool<ReceiveCoin> (
        name:String,
        ticket_price: u8,
        interval:u64,
        max_cap:u64,
        start_time: u64,
        pool_fee:u8,
        settle_fee:u8,
        fee_rate:u8,
        ctx:&mut TxContext
        ){
            pool::create_pool<ReceiveCoin>(name,ticket_price,interval,max_cap,start_time,option::some(tx_context::sender(ctx)),pool_fee,settle_fee,fee_rate,ctx);
        }


    public(package) fun update_pool_status<ReceiveCoin>(pool:&mut Pool<ReceiveCoin>,status:u8){
        pool::update_pool_status(pool,status);
    }

    public(package) fun distribute_and_reset_pool<ReceiveCoin>(pool:&mut Pool<ReceiveCoin>,winner_ticket:&PoolTicket,start_time:u64,end_time:u64,ctx:&mut TxContext){
        pool::distribute_pool(pool,winner_ticket,ctx);
        pool::reset_pool(pool,start_time,end_time);
    }
}