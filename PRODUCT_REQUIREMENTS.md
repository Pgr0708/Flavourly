# Flavourly product requirements

These are release requirements for the recipe, planner, grocery, tracking, and subscription features. The current personalization flow records preferences; recording a preference does not satisfy a requirement to enforce it.

## Food safety and personalization

- Treat each person's allergies as hard exclusions, including separate wheat and gluten restrictions. An imported or suggested recipe with a matching allergen, an unsafe substitution, or unknown allergen information must not enter a plan or grocery list without explicit review.
- Apply dislikes and dietary choices to discovery, imports, suggestions, swaps, and regenerated plans. Keep allergy exclusions in force even when a user changes a plan style.
- Plan around cooking frequency, available days, maximum cooking time, skill, quick meals and snacks, schedule, calorie and macro targets, and household profiles. Offer more than 15 distinct plan styles.
- When no recipes are saved, provide curated discovery and suggestions based on recorded tastes and restrictions.

## Editing and planning

- Let users scale a recipe's servings and recalculate ingredient amounts and grocery quantities.
- Let users remove or substitute ingredients. Save those edits; substitutions must pass the same allergy and dietary checks as original ingredients.
- Let users rearrange meals, swap recipes, and lock meals or ingredients. Regenerating a plan must preserve every locked item and every saved edit.
- Keep edits persistent across app relaunches and plan refreshes. Do not silently restore removed ingredients.
- Consolidate grocery quantities across meals by ingredient and aisle. Let users add, edit, and remove manual grocery items without those items disappearing on plan refresh.

## Tracking and access

- Support meal tracking and Apple Health synchronization with explicit Health permission and clear handling of denied access.
- Use verified RevenueCat entitlement state for Pro access. A paid account must not see repeated Pro upsells.
- Only show purchasable plans and localized prices returned by the current RevenueCat offering. If an expected tier is missing, show it as unavailable rather than inventing a purchase.

## Release checks

- Test wheat and gluten exclusions through import, discovery, substitution, regeneration, and grocery generation.
- Test scaling, ingredient edits, manual grocery items, and locks after relaunch and regeneration.
- Test a paid account, a restored account, canceled purchase, missing offering, and a first-time account.
