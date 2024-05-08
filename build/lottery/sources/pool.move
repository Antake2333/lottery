#[allow(unused_field,unused_const)]
module lottery::pool {
    use sui::coin::{Self,Coin};
    use sui::clock::{Self,Clock};
    use std::string::String;
    use sui::balance::{Self,Balance};
    use sui::table_vec::{Self,TableVec};

    const PoolStatusActive: u8 = 1;

    const PoolStatusInactive: u8 = 0;

    const ErrPoolNotInProcess: u64 = 100;
    const ErrPoolNotEnoughOnetTicket: u64 = 101;
    const ErrPoolNotEnoughtTicket: u64 = 102;
 

    public struct PoolTicket has key, store {
        id: UID,
        pool_id: ID,
        owner_address: address,
        ticket_price: u8,
    }
    
    public struct Pool<phantom ReceiveCoin> has key, store {
        id: UID,
        name: String,
        ticket_price: u8,
        interval: u64, // ms
        max_cap: u64,
        start_time: u64,// ms
        end_time: u64,
        sold_cap: u64,
        total_bonus: Balance<ReceiveCoin>,
        status: u8,
        tickets: TableVec<PoolTicket>,
        pool_fee_address:Option<address>,
        pool_fee:u8, // 万分之
        settle_fee:u8, // 万分之
        fee_rate:u8 // 10000 就是万分之
    }

    public(package) fun create_pool<ReceiveCoin> (
        name:String,
        ticket_price: u8,
        interval:u64,
        max_cap:u64,
        start_time: u64,
        pool_fee_address:Option<address>,
        pool_fee:u8,
        settle_fee:u8,
        fee_rate:u8,
        ctx:&mut TxContext
        ) {
        let end_time = start_time + interval;
        let pool = Pool {
            id: object::new(ctx),
            name: name,
            ticket_price: ticket_price,
            interval: interval, // ms
            max_cap: max_cap,
            start_time: start_time,// ms
            end_time: end_time,
            sold_cap: 0,
            total_bonus: balance::zero<ReceiveCoin>(),
            status: PoolStatusActive,
            tickets: table_vec::empty(ctx),
            pool_fee_address:pool_fee_address,
            pool_fee:pool_fee,
            settle_fee:settle_fee,
            fee_rate:fee_rate
        };
        transfer::public_share_object(pool);
    }

    public(package) fun update_pool_status<ReceiveCoin>(pool:&mut Pool<ReceiveCoin>,status:u8){
        pool.status=status;
    }

    public(package) fun reset_pool<ReceiveCoin>(pool:&mut Pool<ReceiveCoin>,start_time:u64,end_time:u64){
        // once pool settle reset pool
        pool.start_time=start_time;
        pool.end_time=end_time;
        pool.sold_cap=0;
        // send rest coin to admin address
        // move to distribute_pool
        /* if(option::is_some(&pool.reset_address)){
           let rececive_coin = coin::from_balance(balance::withdraw_all(&mut pool.total_bonus),ctx);
           let reset_address= option::borrow<address>(&pool.reset_address);
           transfer::public_transfer(rececive_coin,*reset_address);
        }; */
        if(!table_vec::is_empty(&pool.tickets)){
            while(!table_vec::is_empty(&pool.tickets)){
               let PoolTicket{id,pool_id:_,owner_address:_,ticket_price:_} = table_vec::pop_back(&mut pool.tickets);
               object::delete(id);
            }
        };
    }
    
    #[allow(lint(self_transfer))]
    public(package) fun distribute_pool<ReceiveCoin>(pool:&mut Pool<ReceiveCoin>,
    winner_ticket:&PoolTicket,
    ctx:&mut TxContext){
        // 这里瓜分池子,池子里面还需要一个配置就是,
        // settle_pool的人能分多少,池子手续费多少,然后剩下的全部交给中奖的人
        // 手续费都是万分之 比如 settle_fee = 1 就是万分之1
        if(option::is_some(&pool.pool_fee_address)){
           let mut rececive_coin = coin::from_balance(balance::withdraw_all(&mut pool.total_bonus),ctx);
           let receive_coin_amount= coin::value(&rececive_coin);
           let pool_fee= *&pool.pool_fee as u64;
           let settle_fee =*&pool.settle_fee as u64;
           let fee_rate=*&pool.fee_rate as u64;
           if(pool_fee > 0){
                let pool_fee_coin = coin::split(&mut rececive_coin, 
                receive_coin_amount * pool_fee /  fee_rate
                  ,ctx);
                let reset_address= option::borrow<address>(&pool.pool_fee_address);
                transfer::public_transfer(pool_fee_coin,*reset_address);
           };
           if(settle_fee > 0){
                let settle_fee_coin = coin::split(&mut rececive_coin, 
                receive_coin_amount * settle_fee /  fee_rate
                  ,ctx);
                transfer::public_transfer(settle_fee_coin,tx_context::sender(ctx));
           };
           transfer::public_transfer(rececive_coin,winner_ticket.owner_address);
        };
    }


    #[allow(lint(self_transfer))]
    public(package) fun buy_ticket<ReceiveCoin>(pool:&mut Pool<ReceiveCoin>,mut payment_coin:Coin<ReceiveCoin>,clock: &Clock,ctx:&mut TxContext){
        assert!(!is_inprocess(clock::timestamp_ms(clock),*&pool.start_time,*&pool.end_time,*&pool.status),ErrPoolNotInProcess);
        // 这里总共给了多少coin,除单价就是ticket的张数,剩下的coin返回给购买人
        // 如果coin数量小于单张价格直接返回
        let coin_value=coin::value(&payment_coin);
        let ticket_price=*&pool.ticket_price as u64;
        assert!(coin_value < ticket_price,ErrPoolNotEnoughOnetTicket);
        let ticket_amount= coin_value / ticket_price;
        assert!(ticket_amount + (*&pool.sold_cap) < *&pool.max_cap,ErrPoolNotEnoughtTicket);
        let cost_coin=coin::split(&mut payment_coin,ticket_amount*ticket_price,ctx);
        {
            // 这里先修改pool的数据,然后再创建ticket放到pool中
            *&mut pool.sold_cap = *&pool.sold_cap+ticket_amount;
            balance::join(&mut pool.total_bonus,coin::into_balance(cost_coin));
            let mut i=0;
            while(i < ticket_amount){
                // 这里构造ticket
                let pool_ticket = PoolTicket{
                    id:object::new(ctx),
                    pool_id: object::uid_to_inner(&pool.id),
                    owner_address: tx_context::sender(ctx),
                    ticket_price: *&pool.ticket_price
                };
                table_vec::push_back(&mut pool.tickets,pool_ticket);
                i = i + 1;
            }
        };
        transfer::public_transfer(payment_coin,tx_context::sender(ctx));
    }


    /// check the pool is inprocess
    fun is_inprocess(now_time_stamp:u64, start_time:u64, end_time:u64, status:u8 ) : bool{
        if(status == PoolStatusInactive){
            return false
        }else if(now_time_stamp < start_time){
            return false
        }else if(now_time_stamp > end_time){
            return false
        };
        true
    }
}