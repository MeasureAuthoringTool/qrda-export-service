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

Mongoid.load!("config/mongoid.yml")

use Rack::JSONBodyParser

SCORING = {
  "Proportion" => "PROPORTION",
  "Ratio" => "RATIO",
  "Cohort" => "COHORT",
  "Continuous Variable" => "CONTINUOUS_VARIABLE"
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
# 6. Clean up require statements
# 7. Clean up \class name
# 8. README, including how to run locally instructions
# 9. Log formatting

put "/api/qrda" do
  content_type 'application/json'

  #TODO probably don't need access token here, will remove after SME confirmation
  access_token = request.env["HTTP_Authorization"]
  measure_dto = request.params

  measure = CQM::Measure.new(JSON.parse(measure_dto["measure"]))
  test_cases = measure_dto["testCases"]
  source_data_criteria = measure_dto["sourceDataCriteria"]

  data_criteria = Array.new
  source_data_criteria.each do | criteria |
    data_criteria.push build_source_data_criteria(criteria)
  end

  measure.source_data_criteria = data_criteria

  qrda_errors = {}
  html_errors = {}
  patients = Array.new
  results = Array.new

  test_cases.each_with_index do | test_case, idx |
    qdm_patient = QDM::Patient.new(JSON.parse(test_case["json"]))

    patient = CQM::Patient.new
    patient.qdmPatient = qdm_patient
    patient[:givenNames] = [ test_case["title"] ]
    patient[:familyName] = test_case["series"]
    patients.push patient # For the summary HTML

    expected_values = Array.new
    if test_case["groupPopulations"]
      test_case["groupPopulations"].each do | groupPopulation |
        groupPopulation["populationValues"].each do | populationValue |
          expected_values.push(populationValue["expected"])
        end
      end
    end
    patient[:expectedValues] = expected_values

    if patient.qdmPatient.get_data_elements('patient_characteristic', 'payer').empty?
      payer_codes = [{ 'code' => '1', 'system' => '2.16.840.1.113883.3.221.5', 'codeSystem' => 'SOP' }]
      patient.qdmPatient.dataElements.push QDM::PatientCharacteristicPayer.new(dataElementCodes: payer_codes, relevantPeriod: QDM::Interval.new(patient.qdmPatient.birthDatetime, nil))
    end

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
    results.push << {filename:, qrda:, report:}
  end
  # TODO MAT-6835: measure_patients_summary(patients, nil, qrda_errors, html_errors, measure)
  results.to_json
end

get "/api/health" do
  puts "QRDA Export Service is up"
  "QRDA Export Service is up"
end

def build_source_data_criteria(source_data_criteria)
  data_criteria = instantiate_model(source_data_criteria["type"])
  data_criteria.codeListId = source_data_criteria["oid"]
  data_criteria.description = source_data_criteria["description"]
  data_criteria
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
    return PatientCharacteristicBirthdate.new
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

def measure_patients_summary(patients, results, qrda_errors, html_errors, measure)
  render_to_string partial: "index.html.erb",
                   locals: {
                     measure: measure,
                     results: results,
                     records: patients,
                     html_errors: html_errors,
                     qrda_errors: qrda_errors
                   }
end