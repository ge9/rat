# frozen_string_literal: true

require 'irb'
require 'json'
require 'rackup'
require './tun'
require './nat'
require './nattable'

if ENV['RAT_USE_FIBER']
  require 'async/scheduler'
  require 'falcon'
  require 'rack/handler/falcon'

  Fiber.set_scheduler(Async::Scheduler.new)
  def spawn_thread(_last = false, &block)
    Fiber.schedule(&block)
  end

  def rack_handler
    Rack::Handler::Falcon
  end
else
  require 'webrick'

  def spawn_thread(last = false, &block)
    if last
      yield
    else
      Thread.new(&block)
    end
  end

  def rack_handler
    Rackup::Handler::WEBrick
  end
end

def port_gen(cycle_size, cycle_nums, cycle_starts, portset_offset, portset_size)
  range=[]
  for n in 0...cycle_nums
    start = cycle_starts+(n*cycle_size)+portset_offset;
    v = (start...start+portset_size-1).to_a;
    range.concat(v);
  end
  range
end
def port_gen_v6plus(psid)
  port_gen(4096, 15, 4096, (psid<<4), 16)
end
def port_gen_ocn_vc(psid)
  port_gen(1024, 63, 1024, (psid<<4), 16)
end

$nat = Nat.new

# global address is 192.168.0.139
$nat.global_addr = "\xc0\xa8\x0\x8b".b

# create TCP, UDP, ICMP Echo tables
$nat.tcp_table = RestrictedConeNATTable.new('tcp')
$nat.tcp_table.idle_timeout = 300
$nat.udp_table = RestrictedConeNATTable.new('udp')
$nat.udp_table.idle_timeout = 30
$nat.icmp_echo_table = SymmetricNATTable.new('icmp-echo')
$nat.icmp_echo_table.idle_timeout = 30

# setup ports and logger for each table
[$nat.tcp_table, $nat.udp_table, $nat.icmp_echo_table].each do |table|
  table.global_ports.push(*(9000..9999))
  #table.global_ports=port_gen_v6plus(30)
  table.get_logfp = proc do
    $logfp = open('rat.log', 'a') if $logfp.nil?
    $logfp
  end
end

tun = Tun.new('rat')

# the nat thread (that restarts itself upon exception)
spawn_thread do
  loop do
    loop do
      packet = tun.read
      next unless packet

      # packet.l4.max_segment_size = 1400 if packet.l4.is_a?(TCP) && (packet.l4.flags & TCP::FLAG_SYN) != 0

      packet = $nat.transform(packet)
      next unless packet

      tun.write(packet)
    end
  rescue StandardError => e
    p e.full_message(highlight: false)
  end
end

# Web UI thread
spawn_thread do
  rack_handler.run(proc do |env| $nat.webapp(env) end, Host: '0.0.0.0', Port: 8080)
end

# upon SIGHUP, reset logger and webif state so that they would be reinitialized
Signal.trap('HUP') do
  $logfp = nil
  $nat.reload_webapp
end

# start IRB on the main thread
spawn_thread(true) do
  IRB.start(__FILE__)
end
