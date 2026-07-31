import Foundation

/// Suggests sprite names in flyctl's haikunator style: adjective-noun-token,
/// reimplemented with the same word lists.
public enum Haikunator {
    public static func suggestName(randomNumber: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let adjective = adjectives[randomNumber(adjectives.count)]
        let noun = nouns[randomNumber(nouns.count)]
        let token = randomNumber(9999)
        return "\(adjective)-\(noun)-\(token)"
    }

    // Word lists from flyctl internal/haikunator/haikunator.go.
    static let adjectives = """
        autumn hidden bitter misty silent empty dry dark summer
        icy delicate quiet white cool spring winter patient
        twilight dawn crimson wispy weathered blue billowing
        broken cold damp falling frosty green long late lingering
        bold little morning muddy old red rough still small
        sparkling thrumming shy wandering withered wild black
        young holy solitary fragrant aged snowy proud floral
        restless divine polished ancient purple lively nameless
        amber gentle bright calm silver golden mellow radiant
        soft tranquil velvet lucid rosy tender dusky sunlit
        starlit moonlit windblown graceful mellowed vivid mellowing
        verdant russet glowing drifting rolling humming gleaming
        peaceful faithful agile noble tidy ambered airy cinder
        marbled lustrous dappled kind coral lilac copper willow
        brisk serene curious plucky jaunty earnest honeyed satin
        ivory azure ambergris evergreen rippling glimmering unfurling
        shimmering buoyant wistful
        """.split(separator: /\s+/).map(String.init)

    static let nouns = """
        waterfall river breeze moon rain wind sea morning
        snow lake sunset pine shadow leaf dawn glitter forest
        hill cloud meadow sun glade bird brook butterfly
        bush dew dust field fire flower firefly feather grass
        haze mountain night pond darkness snowflake silence
        sound sky shape surf thunder violet water wildflower
        wave stone resonance branch log dream cherry tree fog
        frost voice paper frog smoke star
        ocean canyon pebble harbor valley blossom petal lantern
        comet aurora meadowlark shell driftwood cove ridge ember
        stream island harborlight seastar meadowland hillside raindrop starlight
        sunbeam moonbeam tide current lagoon harborbird skylark pinecone
        acorn grove orchard garden pathway meadowbrook songbird beacon
        marsh hollow coastline summit inlet woodland headland echo
        horizon overbrook snowfall moonrise sunrise tidepool sandbar fern
        willow reed coral shoreline song meadowstone harborwave glow
        """.split(separator: /\s+/).map(String.init)
}
