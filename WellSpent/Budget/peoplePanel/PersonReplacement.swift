import WellSpentAPI

/// Pure decision logic for `RemoveBudgetPerson`: whether removing a person
/// requires picking someone to reassign their attributions to first.
/// Payment methods aren't modeled yet (Phase 2B), so only income-source
/// attribution matters here — mirrors half of web's `RemovePersonDialog`
/// logic (`WellSpent-web/src/components/budget/peoplePanel/RemovePersonDialog.tsx`).
nonisolated enum PersonReplacement {
    static func needsReplacement(person: Wellspent_V1_BudgetPerson, incomeSources: [Wellspent_V1_IncomeSource]) -> Bool {
        incomeSources.contains { $0.budgetPersonID == person.id }
    }
}
