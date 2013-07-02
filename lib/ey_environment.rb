class EYEnvironment

  def initialize environment_name
    @environment_name = environment_name
    EY.metadata.environment_name = environment_name
  end

  def hostname_for type
    if type.match(/^i-\w{8}$/)
      hostname_for_amazon_id(type)
    else
      hostname_for_type(type)
    end
  end

  private

  attr_reader :environment_name

  def hostname_for_amazon_id amazon_id
    if instance = instances.detect { |x| x['amazon_id'] == amazon_id }
      instance['public_hostname']
    else
      nil
    end
  end

  def hostname_for_type type
    EY.metadata.send(type)
  end

  def instances
    EY.metadata.engine_yard_cloud_api.environment['instances']
  end
end
