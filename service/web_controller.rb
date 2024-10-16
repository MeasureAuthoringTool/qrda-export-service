# frozen_string_literal: true
require 'bundler/setup'
require 'sinatra'
require 'cqm-reports'
require 'cqm/models'
require 'rest-client'
require 'rack'
require 'rack/contrib' # Includes the JSONBodyParser middleware
require 'jwt'

puts "Loading QRDA Export Service"

# Override the as_json method to ensure the _id is displayed as
# just the _id value as a string in the QRDA XML, "<_id>".
# Without this override it will be serialized as extended
# BSON::JSON, "{$oid => "<_id>"}"
module BSON
  class ObjectId
    def as_json(*args)
      to_s.as_json
    end
  end
end

Mongoid.load!("config/mongoid.yml")

use Rack::JSONBodyParser

POPULATION_ABBR = {
  "initialPopulation" => "IPP",
  "measurePopulation" => "MSRPOPL",
  "measurePopulationExclusion" => "MSRPOPLEX",
  "denominator" => "DENOM",
  "numerator" => "NUMER",
  "numeratorExclusion" => "NUMEX",
  "denominatorException" => "DENEXCEP",
  "denominatorExclusion" => "DENEX",
  "stratification" => "STRAT",
  "measureObservation" => "OBSERV",
  "measurePopulationObservation" => "OBSERV"
}

# Implementation pre-reqs
# 1. Parsing JSON input ✅
# 2. Porting over html generation from bonnie ✅
# 3. JWT verification
# 4. Data requirements: ✅ what inputs do we need and where do we get that data from?
#     Looks like we'll only need the madie Measure object. It contains the array of test cases
#     and each testcase already contains an instance of QDM::Patient

# Service stand-up tasks
# 0. github repo ✅
# 1. Bundler setup ✅
# 2. Mongoid config ✅
# 3. Unit testing scaffolding ✅
# 4. RDoc scaffolding
# 5. Containerization ✅
# 6. Clean up require statements ✅
# 7. Clean up \class name ✅
# 8. README, including how to run locally instructions
# 9. Log formatting

put "/api/qrda" do
  # Set return type
  content_type 'application/json'

  # TODO probably don't need access token here, will remove after SME confirmation
  access_token = request.env["HTTP_Authorization"]

  # Parse request params
  measure_dto = request.params # Uses the Rack::JSONBodyParser middleware

  # Prepare CQM Measure
  if measure_dto["measure"].nil?
    return [400, "Measure is empty."]
  end
  madie_measure = JSON.parse(measure_dto["measure"], max_nesting: 512)
  measure = CQM::Measure.new(madie_measure) unless measure_dto["measure"].nil?
  if measure.nil?
    return [400, "Measure is empty."]
  end
  measure.source_data_criteria = build_source_data_criteria(measure_dto["sourceDataCriteria"])
  measure.cms_id = measure.cms_id.nil? ? 'CMS0v0' : measure.cms_id
  measure.hqmf_id = madie_measure["id"]

  test_cases = measure_dto["testCases"]

  qrda_errors = {}
  html_errors = {}
  patients = Array.new
  generated_reports = Array.new # Array of each Patient's QRDA and HTML summary

  # Generate QRDA XMLs and HTML patient summaries
  test_cases.each_with_index do | test_case, idx |
    patient = build_cqm_patient(idx, test_case)
    patients.push patient # For the summary HTML

    filename = "#{idx+1}_#{patient[:familyName]}_#{patient[:givenNames][0]}"

    # generate QRDA
    begin
      qrda = Qrda1R5.new(patient, measure, measure_dto["options"].symbolize_keys).render
    rescue Exception => e
      qrda_errors[patient.id] = e
    end

    # attach the HTML export, or the error
    begin
      report = QdmPatient.new(patient, true).render
    rescue Exception => e
      html_errors[patient.id] = e
    end
    generated_reports.push << {filename:, qrda:, report:}
  end
  summary_report = summary_report(patients,
                                     qrda_errors,
                                     html_errors,
                                     measure,
                                     measure_dto["groupDTOs"])

  return { summaryReport: summary_report, individualReports: generated_reports }.to_json
end

# Helper methods for rendering the Summary Report
helpers do
  def strat_fail(test_case)
    if test_case["stratifications"].nil?
      false
    end
    test_case["stratifications"].any? { |strats| strats["stratificationDtos"].find { |strat| strat["pass"] == false }}
  end

  def pop_fail(test_case)
    test_case["populations"].any? { |pop| pop["pass"] == false }
  end
end

def summary_report(patients, qrda_errors, html_errors, measure, population_results)
  erb "top_level_summary".to_sym, {}, {
    measure: ,
    records: patients,
    html_errors: ,
    qrda_errors: ,
    population_crit_results: population_results,
    population_abbr: POPULATION_ABBR
  }
end

get "/api/health" do
  puts "QRDA Export Service is up"
  "QRDA Export Service is up"
end

def build_source_data_criteria(source_data_criteria)
  data_criteria = Array.new
  source_data_criteria.each do | criteria |
    data_criteria.push map_source_data_criteria(criteria)
  end
  data_criteria
end

def map_source_data_criteria(criteria)
  data_criteria = instantiate_model(criteria["type"])
  data_criteria.codeListId = criteria["oid"]
  data_criteria.description = criteria["description"]
  data_criteria
end

def build_cqm_patient(idx, test_case)
  qdm_patient = QDM::Patient.new(JSON.parse(test_case["json"]))

  patient = CQM::Patient.new
  patient[:id] = idx
  patient.qdmPatient = qdm_patient
  patient[:givenNames] = [test_case["title"]]
  patient[:familyName] = test_case["series"]
  patient[:pass] = true

  if patient.qdmPatient.get_data_elements('patient_characteristic', 'payer').empty?
    payer_codes = [{ 'code' => '1', 'system' => '2.16.840.1.113883.3.221.5', 'codeSystem' => 'SOP' }]
    patient.qdmPatient.dataElements.push QDM::PatientCharacteristicPayer.new(dataElementCodes: payer_codes,
                                                                             relevantPeriod: QDM::Interval.new(patient.qdmPatient.birthDatetime, nil))
  end
  patient
end

def instantiate_model(model_name)
  case model_name
  when "PatientEntity"
    return QDM::PatientEntity.new
  when "CarePartner"
    return QDM::CarePartner.new
  when "RelatedPerson"
    return QDM::RelatedPerson.new
  when "Practitioner"
    return QDM::Practitioner.new
  when "Organization"
    return QDM::Organization.new
  when "Location"
    return QDM::Location.new
  when "PhysicalExamOrder"
    return QDM::PhysicalExamOrder.new
  when "Participation"
    return QDM::Participation.new
  when "PatientCharacteristicSex"
    return QDM::PatientCharacteristicSex.new
  when "CareGoal"
    return QDM::CareGoal.new
  when "PatientCharacteristic"
    return QDM::PatientCharacteristic.new
  when "PatientCharacteristicEthnicity"
    return QDM::PatientCharacteristicEthnicity.new
  when "PatientCharacteristicRace"
    return QDM::PatientCharacteristicRace.new
  when "LaboratoryTestPerformed"
    return QDM::LaboratoryTestPerformed.new
  when "Symptom"
    return QDM::Symptom.new
  when "MedicationAdministered"
    return QDM::MedicationAdministered.new
  when "ProcedureRecommended"
    return QDM::ProcedureRecommended.new
  when "Diagnosis"
    return QDM::Diagnosis.new
  when "CommunicationPerformed"
    return QDM::CommunicationPerformed.new
  when "AssessmentPerformed"
    return QDM::AssessmentPerformed.new
  when "PatientCharacteristicClinicalTrialParticipant"
    return QDM::PatientCharacteristicClinicalTrialParticipant.new
  when "DeviceOrder"
    return QDM::DeviceOrder.new
  when "DiagnosticStudyPerformed"
    return QDM::DiagnosticStudyPerformed.new
  when "InterventionOrder"
    return QDM::InterventionOrder.new
  when "FamilyHistory"
    return QDM::FamilyHistory.new
  when "MedicationActive"
    return QDM::MedicationActive.new
  when "LaboratoryTestOrder"
    return QDM::LaboratoryTestOrder.new
  when "DiagnosticStudyOrder"
    return QDM::DiagnosticStudyOrder.new
  when "SubstanceOrder"
    return QDM::SubstanceOrder.new
  when "PatientCharacteristicPayer"
    return QDM::PatientCharacteristicPayer.new
  when "PatientCharacteristicExpired"
    return QDM::PatientCharacteristicExpired.new
  when "AssessmentOrder"
    return QDM::AssessmentOrder.new
  when "AssessmentRecommended"
    return QDM::AssessmentRecommended.new
  when "ImmunizationAdministered"
    return QDM::ImmunizationAdministered.new
  when "SubstanceAdministered"
    return QDM::SubstanceAdministered.new
  when "EncounterPerformed"
    return QDM::EncounterPerformed.new
  when "EncounterOrder"
    return QDM::EncounterOrder.new
  when "EncounterRecommended"
    return QDM::EncounterRecommended.new
  when "ProcedurePerformed"
    return QDM::ProcedurePerformed.new
  when "Allergy/Intolerance"
    return QDM::AllergyIntolerance.new
  when "PhysicalExamRecommended"
    return QDM::PhysicalExamRecommended.new
  when "PatientCharacteristicBirthdate"
    return QDM::PatientCharacteristicBirthdate.new
  when "AdverseEvent"
    return QDM::AdverseEvent.new
  when "DeviceRecommended"
    return QDM::DeviceRecommended.new
  when "MedicationDischarge"
    return QDM::MedicationDischarge.new
  when "InterventionPerformed"
    return QDM::InterventionPerformed.new
  when "LaboratoryTestRecommended"
    return QDM::LaboratoryTestRecommended.new
  when "MedicationDispensed"
    return QDM::MedicationDispensed.new
  when "DiagnosticStudyRecommended"
    return QDM::DiagnosticStudyRecommended.new
  when "ImmunizationOrder"
    return QDM::ImmunizationOrder.new
  when "PatientCareExperience"
    return QDM::PatientCareExperience.new
  when "ProviderCareExperience"
    return QDM::ProviderCareExperience.new
  when "ProcedureOrder"
    return QDM::ProcedureOrder.new
  when "MedicationOrder"
    return QDM::MedicationOrder.new
  when "SubstanceRecommended"
    return QDM::SubstanceRecommended.new
  when "InterventionRecommended"
    return QDM::InterventionRecommended.new
  when "PhysicalExamPerformed"
    return QDM::PhysicalExamPerformed.new
  when "CommunicationNotPerformed"
    return QDM::CommunicationPerformed.new
  else
    raise "Unsupported data type: #{model_name}"
  end
end
