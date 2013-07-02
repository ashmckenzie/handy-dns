class Server < RExec::Daemon::Base

  $cache = {}

  RUN_AS = 'daemon'
  CACHE_TIME = 86400  # seconds, one day

  INTERFACES = [
    [ :udp, "0.0.0.0", 53 ],
    [ :tcp, "0.0.0.0", 53 ]
  ]

  IN = Resolv::DNS::Resource::IN

  # Default
  #
  # RESOLVER = RubyDNS::Resolver.new(RubyDNS::System::nameservers)

  # Google
  #
  # RESOLVER = RubyDNS::Resolver.new([
  #   [ :udp, "8.8.8.8", 53 ], [ :tcp, "8.8.8.8", 53 ]
  # ])

  # Hooroo
  #
  RESOLVER = RubyDNS::Resolver.new([
   [ :udp, "192.231.203.132", 53 ], [ :tcp, "192.231.203.132", 53],
   [ :udp, "192.231.203.3", 53 ], [ :tcp, "192.231.203.3", 53]
  ])

  def self.run
    $stderr.sync = true

    RubyDNS::run_server(:listen => INTERFACES) do

      on(:start) do
        @logger.level = Logger::INFO
        RExec.change_user(RUN_AS)
      end

      match(/^(?<type>[^\.]+)\.(?<env>[^\.]+)\.ey$/, IN::A) do |transaction, match_data|

        ey_environment = EYEnvironment.new(match_data[:env])

        begin
          if hostname = ey_environment.hostname_for(match_data[:type])

            logger.debug "hostname = #{hostname}"

            if $cache[hostname] && (Time.now.to_i - $cache[hostname][:updated_at]) <= Server::CACHE_TIME
              logger.debug "Cached response #{hostname} (#{$cache[hostname][:ip]})"
              transaction.respond!($cache[hostname][:ip])
            else
              logger.info "Fresh lookup for #{hostname}"

              transaction.defer!

              RESOLVER.query(hostname, IN::A) do |response|
                answer = response.answer.first
                logger.debug "Response: #{answer}"

                if ip = answer[2].address.to_s
                  $cache[hostname] = { ip: ip, updated_at: Time.now.to_i }
                  logger.info "Responding with #{ip} for #{hostname}"
                  transaction.respond!(ip)
                else
                  logger.error "Failed to determine A record for #{hostname}"
                  transaction.failure!(:NXDomain)
                end
              end
            end
          else
            logger.error "Failed to determine EY DNS entry for #{match_data[0]}"
            transaction.failure!(:NXDomain)
          end
        rescue StandardError => e
          logger.error "Failed to determine EY DNS entry for #{match_data[0]}"
        end
      end

      otherwise do |transaction|
        logger.info "Passing DNS request '#{transaction.question}' upstream..."
        transaction.passthrough!(RESOLVER)
      end
    end
  end
end
