import Foundation

/// Turns a free-text goal description ("a weekend trip to Tahoe", "new
/// headphones", "emergency fund for grad school") into a concrete
/// suggested title, target amount, and timeframe — so SetupGoalView isn't
/// limited to the four hardcoded presets, and short-term goals (a
/// weekend, a week) don't get stretched into multi-month plans.
///
/// Reuses the same authenticated Supabase proxy as SavingsCoachService and
/// AIChatService. No static client secret is used.
enum AIGoalBuilderService {
    struct Suggestion: Codable {
        let title: String
        let suggestedAmount: Double
        let suggestedTimeframeDays: Int
        let rationale: String
        let kind: String
        // Present only when "kind" is "custom" and the model was able to
        // picture the specific item — see AIVoxelPart. nil for anything
        // that matched a fixed category (flight, car, furniture, etc.),
        // which use GoalBuildLibrary's hand-built voxels instead.
        let voxels: [AIVoxelPart]?

        enum CodingKeys: String, CodingKey {
            case title
            case suggestedAmount = "suggested_amount"
            case suggestedTimeframeDays = "suggested_timeframe_days"
            case rationale
            case kind
            case voxels
        }

        /// Falls back to `.custom` (the generic gift-box build) if the
        /// model returns something outside the allowed set — a String
        /// field always decodes successfully regardless of its value, so
        /// this is where an unrecognized classification actually gets
        /// caught.
        var goalKind: GoalKind {
            GoalKind(rawValue: kind) ?? .custom
        }

        /// Re-serialized JSON ready to persist on `Goal.customVoxelBlueprintJSON`
        /// and to hand to `GoalBuildLibrary.customVoxels(fromBlueprintJSON:)`.
        /// nil when the model didn't return a "voxels" array at all, or
        /// returned an empty one — either way `goalKind`'s static build
        /// is used instead.
        var voxelBlueprintJSON: String? {
            guard let voxels, !voxels.isEmpty, let data = try? JSONEncoder().encode(voxels) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    static func suggestGoal(from description: String, accessToken: String) async throws -> Suggestion {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "AIGoalBuilder", code: 0, userInfo: [NSLocalizedDescriptionKey: "Describe the goal first."])
        }

        let prompt = """
        You are helping someone set up a savings goal inside a budgeting app called Pocket Vault. \
        The app builds a small 3D voxel sculpture that assembles itself, piece by piece, as they save.

        Their description: "\(trimmed)"

        Respond with ONLY a raw JSON object (no markdown fences, no extra text) in exactly this shape:
        {"title": "short goal title, 3-5 words, title case", "suggested_amount": number in USD with no currency symbol or commas, "suggested_timeframe_days": integer number of days from today until the target date, "rationale": "one short sentence, under 25 words, explaining the amount and timeframe", "kind": "one of exactly: flight, car, gamingRig, emergencyFund, furniture, house, jewelry, custom", "voxels": null or an array (see below)}

        Classify "kind" as whichever category the model will actually look like — pick the closest
        match, don't default to "custom" unless nothing below fits:
        - "flight": any trip, vacation, flight, travel experience
        - "car": a vehicle purchase or down payment
        - "gamingRig": a tech/electronics purchase — computer, console, phone, gadget
        - "emergencyFund": a general safety-net or rainy-day buffer, not tied to buying a specific item
        - "furniture": furniture or home goods — a table, chair, desk, sofa, bed, appliance
        - "house": a home down payment, house, or apartment
        - "jewelry": a ring, wedding/engagement purchase, watch, or other jewelry
        - "custom": the item genuinely doesn't resemble any category above (food, a pet, an \
        instrument, a hobby item, a specific gadget-shaped thing that isn't "gamingRig"-like, etc.)

        If and ONLY if "kind" is "custom", also think like a voxel artist and actually build the \
        thing they described out of simple blocks — don't just describe a generic present. Set \
        "voxels" to an array of 10-24 small parts that, arranged together, silhouette the real \
        object (a bag of cat food should look like a bag, a guitar should look like a guitar body \
        and neck, a bicycle should have two wheels) — not an abstract gift box. Each part is an \
        object: {"x": float, "y": float, "z": float, "mesh": "cube" | "cylinder" | "cone" | \
        "flatSlab", "color": "#RRGGBB", "metallic": bool}. Rules for the voxels:
        - Coordinates are small floats on roughly a 0.09 grid, x and z within -0.4 to 0.4, y within \
        0 to 0.5 (the object sits on a stand — build upward from y=0, don't go below it).
        - Include a small base/pedestal footprint near y=0 using a dark charcoal color \
        (#212633) so it reads as sitting on a display stand, same as every other build in the app.
        - Use colors that actually match the real object (a cat food bag: tan/brown packaging \
        with maybe a red or blue accent stripe; a guitar: wood brown body, black neck) — don't \
        default to generic reds/golds.
        - Set "metallic": true only for small accent pieces that should look like polished metal \
        or glass; everything else false.
        - If "kind" is anything other than "custom", set "voxels" to null — those categories \
        already have a dedicated build.

        Use small values for suggested_timeframe_days (2-10) for weekend trips, single purchases, or \
        one-week goals. Use larger values (90-720) for bigger goals like cars, emergency funds, or \
        vacations that need real saved-up time. Keep the suggested amount realistic and modest for the \
        kind of goal described — a weekend trip should look like a weekend trip's budget, not a \
        vacation home's. Do not include any text outside the JSON object.
        """

        var apiRequest = URLRequest(url: SavingsCoachService.proxyURL)
        apiRequest.httpMethod = "POST"
        apiRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        apiRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["prompt": prompt, "max_tokens": 300]
        apiRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: apiRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "AIGoalBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "API error: \(raw)"])
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String
        else {
            throw NSError(domain: "AIGoalBuilder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't parse response"])
        }

        // The model may still wrap the JSON in ```json fences despite
        // instructions not to — strip those defensively before decoding.
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw NSError(domain: "AIGoalBuilder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't understand that goal — try rephrasing it."])
        }

        guard
            let suggestion = try? JSONDecoder().decode(Suggestion.self, from: jsonData),
            suggestion.suggestedAmount > 0,
            suggestion.suggestedTimeframeDays > 0
        else {
            throw NSError(domain: "AIGoalBuilder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Couldn't understand that goal — try rephrasing it."])
        }

        return suggestion
    }
}
