# frozen_string_literal: true
require "bundler/setup"
require "sinatra"
require "cqm-reports"
require "cqm/models"
require 'rest-client'
require "rack"
require "rack/contrib"
require 'jwt'

puts "Loading QRDA Export Service"

# TODO move config to mongoid.yml file.
# Mongoid.load!("config/mongoid.yml")
Mongoid.configure do |config|
  config.clients.default = {
    hosts: ['host.docker.internal:27017'],
    # hosts: ['localhost:27017'],
    database: 'admin',
  }
end

use Rack::JSONBodyParser

SCORING = {
  "Proportion" => "PROPORTION",
  "Ratio" => "RATIO",
  "Cohort" => "COHORT",
  "Continuous Variable" => "CONTINUOUS_VARIABLE"
}

# Implementation pre-reqs
# 1. Parsing JSON input ✅
# 2. Porting over html generation from bonnie
# 3. JWT verification
# 4. Data requirements: what inputs do we need and where do we get that data from?
#     Looks like we'll only need the madie Measure object. It contains the array of test cases
#     and each testcase already contains an instance of QDM::Patient

# Service stand-up tasks
# 0. github repo ✅
# 1. Bundler setup ✅
# 2. Mongoid config ✅
# 3. Unit testing scaffolding
# 4. RDoc scaffolding
# 5. Containerization ✅
# 6. Clean up require statements
# 7. Clean up \class name
# 8. README, including how to run locally instructions
# 9. Log formatting

put "/api/qrda" do
  content_type 'text/xml'

  measure = request.params
  test_cases = measure["testCases"]

  start_time = DateTime.parse(measure["measurementPeriodStart"])
  end_time = DateTime.parse(measure["measurementPeriodEnd"])
  options = { start_time: start_time, end_time: end_time }

  qrdas = Array.new
  test_cases.each do | test_case |

    qdm_patient = QDM::Patient.new(JSON.parse(test_case["json"]))

    patient = CQM::Patient.new
    patient.qdmPatient = qdm_patient
    patient[:givenNames] = [test_case["title"]]

    # TODO Map MADiE Measure to CQM::Measure
    qrdas.push Qrda1R5.new(patient, [map_madie_to_cqm_measure(measure)], options).render
  end
  qrdas
end

get "/api/health" do
  puts "QRDA Export Service is up"
  "QRDA Export Service is up"
end

def map_madie_to_cqm_measure(madie_measure)
  msr = CQM::Measure.new
  msr.description = madie_measure["measureName"]
  msr.title = madie_measure["measureName"]
  msr.hqmf_id = madie_measure["id"] #maybe?
  msr.hqmf_set_id = madie_measure["measureSetId"] #maybe?
  msr.hqmf_version_number = madie_measure["version"]
  msr.cms_id = madie_measure["cmsId"] unless madie_measure["cmsId"].nil?
  msr.measure_scoring = SCORING[madie_measure["scoring"]]

  #TODO map population criteria
  msr
end