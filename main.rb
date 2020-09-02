require 'open3'
require 'plist'
require 'fileutils'
require 'securerandom'

###### Enviroment Variable Check
def env_has_key(key)
	return (ENV[key] != nil && ENV[key] !="") ? ENV[key] : abort("Missing #{key}.")
end

$temporary_path = env_has_key("AC_TEMP_DIR")
$temporary_path += "/appcircle_install_certificate_and_profile"

###### Run Command Function
def run_command(command,skip_abort)
  puts "@@[command] #{command}"
  status = nil
  stdout_str = nil
  stderr_str = nil
  Open3.popen3(command) do |stdin, stdout, stderr, wait_thr|
    stdout.each_line do |line|
      puts line
    end
    stdout_str = stdout.read
    stderr_str = stderr.read
    status = wait_thr.value
  end

  unless status.success?
    if skip_abort
      puts stderr_str
    else
      abort_script(stderr_str)
    end
  end
end

def abort_script(error)
  abort("#{error}")
end

###### Import Certificate & Provisioning
def create_keychain()
  keychain_path = "#$temporary_path/#{SecureRandom.uuid}.keychain"
  keychain_password = [*('a'..'z'),*('0'..'9')].shuffle[0,16].join

  command_create_keychain = "security create-keychain -p #{keychain_password} \"#{keychain_path}\""
    run_command(command_create_keychain,false)
  
    command_set_settings = "security set-keychain-settings \"#{keychain_path}\""
    run_command(command_set_settings,false)
  
    command_unlock_keychain = "security unlock-keychain -p #{keychain_password} \"#{keychain_path}\""
    run_command(command_unlock_keychain,false)

    command_list = "security list-keychain -d user"
    run_command(command_list,false)
  
    command_list_s = "security list-keychain -d user -s $(security list-keychains -d user | sed -e s/\\\"//g) \"#{keychain_path}\""
    run_command(command_list_s,false)
  
    command_list2 = "security list-keychain -d user"
  run_command(command_list2,false)
  
  return keychain_path,keychain_password
end

def import_certificate(keychain_path)
  cert_string = $certificates

  cert_array = []
  split_cert_string = cert_string.split("|")
  
  split_cert_length = split_cert_string.length
  x = 0
  while x < split_cert_length
      cert = {"certificate" => "#{split_cert_string[x+1]}", "password"=> "#{split_cert_string[x]}"}
    cert_array.push(cert)
    x += 2
  end

  cert_array.each_with_index do |data,index|
    command_import_certificate = "security import #{data["certificate"]} -P \"#{data["password"]}\" -A -t cert -f pkcs12 -k \"#{keychain_path}\""
    run_command(command_import_certificate,false)
  end

  return cert_array
end

def import_provisioning_profile()
  provisioning_profiles_string = $provisioning_profiles
  provisioning_profile_array = provisioning_profiles_string.split("|")

  unless File.directory?(ENV['HOME'] + '/Library/MobileDevice')
    FileUtils.mkdir_p ENV['HOME']+'/Library/MobileDevice/Provisioning Profiles'
  end
  

  provisioning_object_array = []
  
  provisioning_profile_array.each_with_index do |data,index|
  
    provisioning_profile_plist = "#{File.dirname(data)}/_xcodeprovisioningprofiletmp.plist"
    command_cms = "security cms -D -i #{data}"
    run_command(command_cms,false)
    run_command("#{command_cms} > #{provisioning_profile_plist}",false)
  
    command_uuid = "/usr/libexec/PlistBuddy -c \"Print UUID\" \"#{provisioning_profile_plist}\""
    puts command_uuid
    uuid = `#{command_uuid}`.chomp
    puts uuid
  
    command_copy = "cp -f #{data} ~/Library/MobileDevice/Provisioning\\ Profiles/#{uuid}.mobileprovision"
    run_command(command_copy,false)
    
    profile = {"uuid" => "#{uuid}", "provisioningProfile"=> "#{data}"}
    provisioning_object_array.push(profile)
  end
  
  puts "Provisioning Profiles : #{provisioning_object_array}"
end

# AC_CERTIFICATES
# "password|/Users/..|password|/Users/.."
if  ENV["AC_CERTIFICATES"] == nil || ENV["AC_CERTIFICATES"] ==""
  puts "AC_CERTIFICATES does not exist."
else
  $certificates = ENV["AC_CERTIFICATES"]
  $keychain_path,$keychain_password = create_keychain()
  $certificate_array = import_certificate($keychain_path)
end

# AC_PROVISIONING_PROFILES
if  ENV["AC_PROVISIONING_PROFILES"] == nil || ENV["AC_PROVISIONING_PROFILES"] ==""
  puts "AC_PROVISIONING_PROFILES does not exist."
else
  $provisioning_profiles = ENV["AC_PROVISIONING_PROFILES"]
  import_provisioning_profile()
end

puts "AC_KEYCHAIN_PATH : #{$keychain_path}"
puts "AC_KEYCHAIN_PASSWORD : #{$keychain_password}"

### Write Environment Variable
open(ENV['AC_ENV_FILE_PATH'], 'a') { |f|
  f.puts "AC_KEYCHAIN_PATH=#{$keychain_path}"
  f.puts "AC_KEYCHAIN_PASSWORD=#{$keychain_password}"
}

exit 0