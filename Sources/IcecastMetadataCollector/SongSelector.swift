import Maxi80Backend

func selectBestMatch(_ response: AppleMusicSearchResponse) -> Song? {
    guard let songs = response.results.songs?.data else { return nil }
    // Prefer songs that have artwork
    return songs.first { $0.attributes.artwork != nil } ?? songs.first
}
