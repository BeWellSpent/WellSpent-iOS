import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("AddEditIncomeViewModel")
@MainActor
struct AddEditIncomeViewModelTests {
    private func makeViewModel(
        mode: AddEditIncomeViewModel.Mode = .add,
        countryCode: String = "US"
    ) -> AddEditIncomeViewModel {
        AddEditIncomeViewModel(
            mode: mode,
            budgetProfileID: "profile-1",
            countryCode: countryCode,
            currencyCode: "USD",
            authenticatedClient: APIClient.makePublicClient(baseURL: "http://localhost:1")
        )
    }

    @Test("submit is disabled until name and a valid amount are present")
    func canSubmitReflectsFormState() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.name = "Paycheck"
        #expect(!viewModel.canSubmit)

        viewModel.amountText = "not-a-number"
        #expect(!viewModel.canSubmit)

        viewModel.amountText = "2500.50"
        #expect(viewModel.canSubmit)
    }

    @Test("rejects a negative amount")
    func rejectsNegativeAmount() {
        let viewModel = makeViewModel()
        viewModel.name = "Paycheck"
        viewModel.amountText = "-100"
        #expect(!viewModel.canSubmit)
    }

    @Test("parses whole and fractional amounts into units/nanos")
    func parseAmount() {
        let whole = AddEditIncomeViewModel.parseAmount("2500")
        #expect(whole?.units == 2500)
        #expect(whole?.nanos == 0)

        let fractional = AddEditIncomeViewModel.parseAmount("2500.5")
        #expect(fractional?.units == 2500)
        #expect(fractional?.nanos == 500_000_000)
    }

    @Test("rejects empty, non-numeric, or negative amounts")
    func parseAmountRejectsInvalid() {
        #expect(AddEditIncomeViewModel.parseAmount("") == nil)
        #expect(AddEditIncomeViewModel.parseAmount("abc") == nil)
        #expect(AddEditIncomeViewModel.parseAmount("-5") == nil)
    }

    @Test("before-tax toggle only shows for US budgets")
    func beforeTaxVisibility() {
        #expect(makeViewModel(countryCode: "US").showBeforeTaxToggle)
        #expect(!makeViewModel(countryCode: "AR").showBeforeTaxToggle)
        #expect(!makeViewModel(countryCode: "ES").showBeforeTaxToggle)
    }

    @Test("editing an existing source pre-fills its fields")
    func editModePrefill() {
        let source = Wellspent_V1_IncomeSource.with {
            $0.id = 42
            $0.name = "Freelance"
            $0.incomeType = .freelance
            $0.defaultAmount = .with {
                $0.units = 1200
                $0.nanos = 0
                $0.currency = "USD"
            }
            $0.recurring = false
            $0.budgetPersonID = 7
            $0.paymentFrequency = .monthly
            $0.beforeTax = true
        }
        let viewModel = makeViewModel(mode: .edit(source), countryCode: "US")

        #expect(viewModel.name == "Freelance")
        #expect(viewModel.incomeType == .freelance)
        #expect(viewModel.amountText == "1200")
        #expect(viewModel.recurring == false)
        #expect(viewModel.personID == 7)
        #expect(viewModel.beforeTax == true)
    }
}
