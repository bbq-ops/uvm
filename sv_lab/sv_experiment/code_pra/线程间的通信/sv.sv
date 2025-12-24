class car;
    mailbox tmp_mb,spd_mb,fuel_mb;
    int sample_period;
    
    function new();
        sample_period = 10;
        tmp_mb = new();
        spd_mb = new();
        fuel_mb = new();
    endfunction
    
    task sensor_tmp;
        int tmp;
        forever begin
            std::randomize(tmp) with {tmp >= 80 && tmp <= 100;};
            tmp_mb.put(tmp);
            #sample_period;
        end
    endtask
    
    task sensor_spd;
        int spd;
        forever begin
            std::randomize(spd) with {spd >= 50 && spd <= 60;};
            spd_mb.put(spd);
            #sample_period;
        end
    endtask
    
    task sensor_fuel;
        int fuel;
        forever begin
            std::randomize(fuel) with {fuel >= 30 && fuel <= 35;};
            fuel_mb.put(fuel);
            #sample_period;
        end
    endtask
    
    task drive();
        fork
            sensor_tmp();
            sensor_spd();
            sensor_fuel();
            display(tmp_mb,"temperature");  //这里是display任务，不是那个系统函数
            display(spd_mb,"speed");
            display(fuel_mb,"fuel");
        join_none
    endtask
    
    task display(mailbox mb,string name = "mb");
        int val;
        forever begin
            mb.get(val);
            $display("car::%s is %0d",name,val);
        end
    endtask
endclass




//------------------------------------------------- //
// 定义car类，通过event（事件）实现两个任务（stall和park）的时序同步
class car;
  // 声明两个事件，用于任务间的信号通知（类似"触发器"）
  // e_stall：用于stall任务通知park任务"可以开始执行"
  // e_park：用于park任务通知stall任务"已完成执行"
  event e_stall;
  event e_park;
  
  // stall任务：模拟"停车熄火"过程，通过事件与park任务同步
  task stall;
    $display("car::stall started");  // 打印任务启动信息（时间点：t=0）
    
    #1ns;  // 模拟熄火过程的耗时（延迟1ns，时间推进到t=1ns）
    
    -> e_stall;  // 触发e_stall事件，通知等待该事件的park任务"可以开始"
    
    @e_park;  // 等待e_park事件被触发（阻塞在此，直到park任务完成后触发该事件）
    
    $display("car::stall finished");  // 收到e_park事件后，打印任务结束信息
  endtask
  
  // park任务：模拟"泊车"过程，依赖stall任务的事件通知才能启动
  task park;
    @e_stall;  // 等待e_stall事件被触发（阻塞在此，直到stall任务触发该事件）
    
    $display("car::park started");  // 收到e_stall事件后，打印任务启动信息（时间点：t=1ns）
    
    #1ns;  // 模拟泊车过程的耗时（延迟1ns，时间推进到t=2ns）
    
    -> e_park;  // 触发e_park事件，通知等待该事件的stall任务"已完成"
    
    $display("car::park finished");  // 打印任务结束信息（时间点：t=2ns）
  endtask
  
  // drive任务：并行启动stall和park任务，触发整个同步流程
  task drive();
    fork  // fork-join_none：子任务并行执行，父任务不阻塞，立即返回
      this.stall();  // 启动stall任务
      this.park();   // 启动park任务
    join_none
  endtask
endclass

//------------------------------------------------- //
class car;
  // 声明semaphore类型的`key`，用于实现`stall`和`park`任务的同步（基于“令牌”机制控制任务执行顺序）
  semaphore key;

  // 构造函数：初始化semaphore，设置初始“令牌”计数为0（初始无可用令牌）
  function new();
    key = new(0);
  endfunction

  // stall任务：模拟“停车熄火”流程，通过semaphore与`park`任务同步
  task stall;
    $display("car::stall started");  // 打印任务启动日志
    #1ns;  // 模拟熄火过程的耗时（延迟1ns）
    key.put();  // 释放1个“令牌”（semaphore计数+1）
    key.get();  // 获取“令牌”（若计数为0则阻塞，直到有令牌可用）
    $display("car::stall finished");  // 拿到令牌后，打印任务结束日志
  endtask

  // park任务：模拟“泊车”流程，通过semaphore与`stall`任务同步
  task park;
    key.get();  // 获取“令牌”（初始计数为0，因此会阻塞，直到`stall`任务释放令牌）
    $display("car::park started");  // 拿到令牌后，打印任务启动日志
    #1ns;  // 模拟泊车过程的耗时（延迟1ns）
    key.put();  // 释放“令牌”（semaphore计数+1，供`stall`任务的`key.get()`使用）
    $display("car::park finished");  // 释放令牌后，打印任务结束日志
  endtask

  // drive任务：并行启动`stall`和`park`任务，触发整个同步流程
  task drive();
    fork  // fork-join_none：子任务并行执行，父任务不阻塞、立即返回
      this.stall();  // 启动`stall`任务
      this.park();   // 启动`park`任务
    join_none
  endtask
endclass

//------------------------------------------------- //
class car;
    mailbox mb;
    
    function new();
        mb = new(1);
    endfunction
    
    task stall;
        int val = 0;
        $display("car::stall started");
        #1ns;
        mb.put(val);
        mb.get(val);
        $display("car::stall finished");
    endtask
    
    task park;
        int val = 0;
        mb.get(val);
        $display("car::park started");
        #1ns;
        mb.put(val);
        $display("car::park finished");
    endtask
    
    task drive();
    fork
        this.stall();
        this.park();
    join_none
    endtask
endclass






















