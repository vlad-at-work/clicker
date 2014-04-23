require "rubygems"
require "parseconfig"
require "faster_csv"
require "hpricot"
require "pp"

puts "Error: no configuration file ('clicker.conf') not found" if not File::exists?('clicker.conf')
$config = ParseConfig.new('clicker.conf')
$current_ip = '127.0.0.1'
$phrase_ip = Hash.new

def switch_proxy
  # if you have a list of proxies, put them here.
  proxies = ["1.2.3.4", "5.6.7.8"]

  proxies.each do |p| 
    if $phrase_ip[p].nil?
      $phrase_ip[p] = Array.new
    end
  end
  address = proxies.sort_by { rand }.first
  $current_ip = address
  network_device = $config.get_value('network_device')
  `networksetup -setwebproxy #{network_device} #{address} 3128`
  `networksetup -setwebproxystate #{network_device} on`
  `networksetup -getwebproxy #{network_device}`

  case $config.get_value('browser')
  when "firefox"
    `killall -9 firefox-bin >> /dev/null 2>&1`
    $browser = Watir::Browser.new(:firefox)
  when "chrome"
    $browser = Watir::Browser.new(:chrome)
  when "safari"
    `killall -9 Safari >> /dev/null 2>&1`
    `rm ~/Library/Cookies/Cookies.plist`;
    `rm ~/Library/Safari/History*.*`;
    sleep(1)
    $browser = Watir::Safari.new
  end
  
  sleep(1)
end

def disable_proxy
  network_device = $config.get_value('network_device')
  puts `sudo networksetup -setwebproxystate #{network_device} off`
end

def wait_delay
  if $config.get_value('random_delay')
    rand(4)
  else
    4
  end
end

def ip_hasnt_been_used_for_keyword(p)
  if $phrase_ip[$current_ip].include?(p)
    puts "---> error ip[#{$current_ip}] has already been used for phrase [#{p}], regenerating"
    return false
  else
    puts "---> system proxy set to [#{$current_ip}]"
    $phrase_ip[$current_ip] << p
    return true
  end
end

def click_if_exist(browser, domain, pagenumber = 1)
  begin
    for pagenumber in 1..5
      if $browser.html.include?(domain)
        doc = Hpricot(browser.html)        
        puts "Found #{domain} link on page #{pagenumber}, clicking it"
        
        (doc/"a").each do |link|
          if link.attributes['href']
            if link.attributes['href'].include?(domain.to_s)
              browser.link(:text, link.inner_text).click
              sleep(wait_delay)
            end
          end
        end
        
        return true
      end
      $browser.link(:text, (pagenumber+1).to_s).click unless pagenumber >= 5
      sleep(wait_delay)
    end
  rescue Exception => e
    pp e
    return true
  end
end

case $config.get_value('browser')
  when "firefox"
    require "watir-webdriver"
    $browser = Watir::Browser.new(:firefox)
  when "chrome"
    require "watir-webdriver"
    $browser = Watir::Browser.new(:chrome)
  when "safari"
    require "safariwatir"
    $browser = Watir::Safari.new
end

switch_proxy

begin
  clickerdata = FasterCSV.read("clicker.db", :force_quotes => true, :quote_char => "'", :col_sep =>',', :row_sep =>:auto)
  
  counter = 0
  record_count = clickerdata.length
  start_time = Time.now
  start_timestamp = Time.now.to_i
  
  puts "Started at " + start_time.inspect
  
  total_search_count = 0

  clickerdata.shuffle.each do |row|
    
    counter += 1
    
    current_timestamp = Time.now.to_i
    elapsed_time_full = Time.utc(current_timestamp - start_timestamp)
    elapsed_time = elapsed_time_full.hour.to_s + "hrs " + elapsed_time_full.min.to_s + "mins"
    
    puts "******************** Processing record #{counter}/#{record_count}/#{total_search_count} (#{elapsed_time})"
    phrase = row[0]
    phrase = phrase.scan(/'(.+?)'|"(.+?)"|([^ ]+)/).flatten.compact

    domain = row[1]
    domain = domain.scan(/'(.+?)'|"(.+?)"|([^ ]+)/).flatten.compact

	  next if domain.blank?

    num1 = rand(15)
    num2 = 15 + rand(15)
    times_to_do = num1 + rand(num2)

    total_search_count += times_to_do

    times_to_do.times do |x|
      begin
        until ip_hasnt_been_used_for_keyword(phrase) do
          switch_proxy
        end
        puts "---> [#{$current_ip}] srch [#{phrase}] pos [#{x}/#{times_to_do}]"
        #case $config.get_value('searchengine')
        searchengine = ['bing','google','yahoo'].sort_by { rand }.first
        case searchengine
        when "bing"
          $browser.goto("http://www.bing.com")
        when "google"
          $browser.goto("http://www.google.com")
        when  "yahoo"
          $browser.goto("http://www.yahoo.com")        
        end
        sleep(wait_delay)
        case searchengine
        when "bing"
          $browser.text_field(:name, "q").set phrase
        when "google"
          $browser.text_field(:name, "q").set phrase
        when  "yahoo"
          $browser.text_field(:name, "p").set phrase       
        end
        sleep(wait_delay)
        case searchengine
        when "bing"
          $browser.button(:id, "sb_form_go").click
        when "google"
          $browser.button(:name, "btnG").click
        when "yahoo"
          $browser.button(:id, "search-submit").click
          end   
        sleep(wait_delay)
        click_if_exist($browser, domain.to_s, 1)
        switch_proxy
      rescue Exception => e
        pp e
        retry
      end
    end
  end
rescue Exception => e
  pp e
  retry
end

Puts "DONE. Did #{counter} records, with a total of #{total_search_count} searches, in #{elapsed_time}"

disable_proxy