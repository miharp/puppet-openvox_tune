# frozen_string_literal: true

require 'docker'
require 'voxpupuli/acceptance/spec_helper_acceptance'

# beaker-docker gives up on an image build after 300 seconds unless a timeout
# is already set. On GitHub's runners the EL image builds, which usually take
# under a minute, now and then run past that, failing the job before any
# example runs. Allow 15 minutes.
Docker.options = (Docker.options || {}).merge(read_timeout: 900, write_timeout: 900)

configure_beaker
