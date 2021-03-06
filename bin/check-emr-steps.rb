#! /usr/bin/env ruby
#
# check-emr-steps
#
# DESCRIPTION:
#   Alerts on any failed steps for a cluster in the past 10 minutes.
#
# OUTPUT:
#   plain-text
#
#
# DEPENDENCIES:
#   gem: aws-sdk
#   gem: sensu-plugin
#
# USAGE:
#   check-emr-steps.rb -r us-west-2 -b 'My Cluster'
#
#   This will alert on any failed steps in the past 10 minutes on the latest cluster
#   with the name 'My Cluster'.
# NOTES:
#
# LICENSE:
#   Bryan Absher <bryan.absher@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.

require 'sensu-plugins-aws'
require 'sensu-plugin/metric/cli'
require 'aws-sdk'

class CheckEMRSteps < Sensu::Plugin::Metric::CLI::Graphite
  include Common

  option :scheme,
         description: 'Metric naming scheme, text to prepend to metric',
         short: '-s SCHEME',
         long: '--scheme SCHEME',
         default: 'sensu.aws.emr'

  option :aws_region,
         short: '-r AWS_REGION',
         long: '--aws-region REGION',
         description: 'AWS Region (defaults to us-east-1).',
         default: 'us-east-1'

  option :cluster_name,
         short: '-b CLUSTER_NAME',
         long: '--cluster-name',
         description: 'The name of the EMR cluster',
         required: true

  def run
    emr = Aws::EMR::Client.new(aws_config)
    begin
      emr_clusters = emr.list_clusters.clusters
      clusters = emr_clusters.select { |c| c.name == config[:cluster_name] }
      critical "EMR cluster #{config[:cluster_name]} not found" if clusters.empty?
      cluster = clusters.sort_by { |c| c.status.timeline.creation_date_time }.reverse.first

      steps = emr.list_steps(
        cluster_id: cluster.id,
        step_states: ['FAILED']
      ).steps

      messages = []
      now = Time.new
      failed = steps.select { |step| now - step.status.timeline.end_date_time < 10 * 60 }
      failed.each_entry { |step| messages << "Step #{step.id} '#{step.name}' has failed on cluster #{cluster.id} '#{cluster.name}'" }

      if messages.count > 0
        critical("#{messages.count} #{messages.count > 1 ? 'steps have' : 'step has'} failed: #{messages.join(',')}")
      else
        ok
      end
    end
  end
end
