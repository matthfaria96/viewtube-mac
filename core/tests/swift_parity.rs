//! Os mesmos casos de `Tests/ViewTubeCoreTests` (Swift), um teste por teste. Se um lado mudar de
//! comportamento, o outro precisa mudar junto.

use viewtube_core::links::{parse_incoming, parse_incoming_text, ClipboardOffer, RemoteCommand, BOOKMARKLET};
use viewtube_core::lyrics::{self, Line};
use viewtube_core::navigation::{self, Decision};
use viewtube_core::{sponsorblock, time_param, web_asset, PlayerMode, PrefCookie, VideoRef};

use PlayerMode::{Music, Youtube};

fn vref(id: &str) -> VideoRef {
    VideoRef::new(id)
}

// MARK: VideoRefTests

#[test]
fn video_ref_parses_watch_url() {
    assert_eq!(VideoRef::parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), Some(vref("dQw4w9WgXcQ")));
}

#[test]
fn video_ref_parses_playlist_and_time() {
    let parsed = VideoRef::parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&t=1m30s");
    assert_eq!(parsed, Some(vref("dQw4w9WgXcQ").with_playlist("PL123").with_start_time(Some(90.0))));
}

#[test]
fn video_ref_parses_short_link() {
    assert_eq!(VideoRef::parse("https://youtu.be/dQw4w9WgXcQ?t=42"), Some(vref("dQw4w9WgXcQ").with_start_time(Some(42.0))));
}

#[test]
fn video_ref_parses_music_mobile_shorts_live_and_embed() {
    let id = |u: &str| VideoRef::parse(u).map(|r| r.video_id);
    assert_eq!(VideoRef::parse("https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVM1").unwrap().playlist_id.as_deref(), Some("RDAMVM1"));
    assert_eq!(id("https://m.youtube.com/watch?v=dQw4w9WgXcQ").as_deref(), Some("dQw4w9WgXcQ"));
    assert_eq!(id("https://www.youtube.com/shorts/dQw4w9WgXcQ").as_deref(), Some("dQw4w9WgXcQ"));
    assert_eq!(id("https://www.youtube.com/live/dQw4w9WgXcQ").as_deref(), Some("dQw4w9WgXcQ"));
    assert_eq!(VideoRef::parse("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=10").unwrap().start_time, Some(10.0));
}

#[test]
fn video_ref_rejects_non_youtube_and_invalid_ids() {
    for u in [
        "https://vimeo.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/watch?v=short",
        "https://www.youtube.com/watch?v=dQw4w9WgXc!",
        "https://www.youtube.com/feed/subscriptions",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
    ] {
        assert_eq!(VideoRef::parse(u), None, "{u}");
    }
}

#[test]
fn video_ref_builds_youtube_url_with_time() {
    let video = vref("dQw4w9WgXcQ").with_playlist("PL1").with_start_time(Some(61.8));
    assert_eq!(video.url_for(Youtube), "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1&t=61s");
}

#[test]
fn video_ref_builds_music_url_without_time_parameter() {
    assert_eq!(vref("dQw4w9WgXcQ").with_start_time(Some(61.0)).url_for(Music), "https://music.youtube.com/watch?v=dQw4w9WgXcQ");
}

#[test]
fn video_ref_omits_zero_time() {
    assert_eq!(vref("dQw4w9WgXcQ").with_start_time(Some(0.4)).url_for(Youtube), "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
}

#[test]
fn video_ref_maps_liked_lists_between_modes() {
    assert_eq!(vref("dQw4w9WgXcQ").with_playlist("LM").url_for(Youtube), "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=LL");
    assert_eq!(vref("dQw4w9WgXcQ").with_playlist("LL").url_for(Music), "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=LM");
    assert_eq!(vref("dQw4w9WgXcQ").with_playlist("WL").url_for(Music), "https://music.youtube.com/watch?v=dQw4w9WgXcQ");
}

#[test]
fn video_ref_with_time_returns_copy() {
    let original = vref("dQw4w9WgXcQ");
    let moved = original.with_start_time(Some(12.0));
    assert_eq!(original.start_time, None);
    assert_eq!(moved.start_time, Some(12.0));
}

// MARK: CrossModeTests

#[test]
fn cross_mode_content_links_go_to_the_other_mode() {
    assert_eq!(navigation::cross_mode_target("https://music.youtube.com/watch?v=dQw4w9WgXcQ", Youtube), Some(Music));
    assert_eq!(navigation::cross_mode_target("https://music.youtube.com/", Youtube), Some(Music));
    assert_eq!(navigation::cross_mode_target("https://www.youtube.com/watch?v=dQw4w9WgXcQ", Music), Some(Youtube));
    assert_eq!(navigation::cross_mode_target("https://youtu.be/dQw4w9WgXcQ", Music), Some(Youtube));
}

#[test]
fn cross_mode_same_mode_stays_here() {
    assert_eq!(navigation::cross_mode_target("https://www.youtube.com/watch?v=dQw4w9WgXcQ", Youtube), None);
    assert_eq!(navigation::cross_mode_target("https://music.youtube.com/search?q=x", Music), None);
}

#[test]
fn cross_mode_account_and_consent_flows_are_never_diverted() {
    for (u, m) in [
        ("https://consent.youtube.com/m?continue=x", Music),
        ("https://accounts.youtube.com/accounts/SetSID", Music),
        ("https://www.youtube.com/signin?next=x", Music),
        ("https://www.youtube.com/logout", Music),
        ("https://www.youtube.com/create_channel", Music),
        ("https://www.youtube.com/account", Music),
        ("https://accounts.google.com/ServiceLogin", Youtube),
    ] {
        assert_eq!(navigation::cross_mode_target(u, m), None, "{u}");
    }
}

// MARK: HardeningTests

#[test]
fn hardening_time_param_rejects_infinite_and_huge_values() {
    for t in ["inf", "1e400", "99999999999999999999", "99999999h", "nan"] {
        assert_eq!(time_param::parse(t), None, "{t}");
    }
}

#[test]
fn hardening_crazy_link_time_does_not_crash() {
    let request = parse_incoming("viewtube://open?url=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ&t=inf").unwrap();
    assert_eq!(request.video.as_ref().unwrap().video_id, "dQw4w9WgXcQ");
    assert_eq!(request.video.unwrap().start_time, None);
}

#[test]
fn hardening_url_building_clamps_time() {
    assert_eq!(vref("dQw4w9WgXcQ").with_start_time(Some(f64::INFINITY)).url_for(Youtube), "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    assert_eq!(vref("dQw4w9WgXcQ").with_start_time(Some(1e300)).url_for(Youtube), "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
}

#[test]
fn hardening_only_web_and_mail_links_open_outside() {
    assert_eq!(navigation::decision("file:///Applications/Utilities/Terminal.app"), Decision::Block);
    assert_eq!(navigation::decision("otherapp://do-something"), Decision::Block);
    assert_eq!(navigation::decision("mailto:a@b.c"), Decision::OpenExternally("mailto:a@b.c".into()));
}

#[test]
fn hardening_redirect_only_follows_web_targets() {
    let file = "https://www.youtube.com/redirect?q=file%3A%2F%2F%2FApplications%2FUtilities%2FTerminal.app";
    assert_eq!(navigation::decision(file), Decision::Block);
    let web = "https://www.youtube.com/redirect?q=https%3A%2F%2Fexample.com";
    assert_eq!(navigation::decision(web), Decision::OpenExternally("https://example.com".into()));
}

#[test]
fn hardening_user_published_google_hosts_are_not_internal() {
    assert_ne!(navigation::decision("https://sites.google.com/view/x"), Decision::Allow);
    assert_ne!(navigation::decision("https://script.googleusercontent.com/x"), Decision::Allow);
    assert_eq!(navigation::decision("https://accounts.google.com/signin"), Decision::Allow);
}

#[test]
fn hardening_incoming_link_rejects_redirect_pages() {
    assert_eq!(parse_incoming("viewtube://open?url=https%3A%2F%2Fwww.youtube.com%2Fredirect%3Fq%3Dfile%3A%2F%2F%2Fetc"), None);
}

// MARK: IncomingLinkTests

fn encode_all(text: &str) -> String {
    text.bytes().map(|b| if b.is_ascii_alphanumeric() { (b as char).to_string() } else { format!("%{b:02X}") }).collect()
}

#[test]
fn incoming_bookmarklet_open_link() {
    let encoded = encode_all("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL9");
    let request = parse_incoming(&format!("viewtube://open?url={encoded}&t=75")).unwrap();
    assert_eq!(request.mode, Youtube);
    assert_eq!(request.video, Some(vref("dQw4w9WgXcQ").with_playlist("PL9").with_start_time(Some(75.0))));
    assert_eq!(request.url, "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL9&t=75s");
}

#[test]
fn incoming_bookmarklet_from_music_keeps_music_mode() {
    let request = parse_incoming("viewtube://open?url=https%3A%2F%2Fmusic.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&t=10").unwrap();
    assert_eq!(request.mode, Music);
    assert_eq!(request.video.as_ref().unwrap().start_time, Some(10.0));
    assert_eq!(request.url, "https://music.youtube.com/watch?v=dQw4w9WgXcQ");
}

#[test]
fn incoming_zero_time_from_bookmarklet_keeps_link_time() {
    let request = parse_incoming("viewtube://open?url=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ%3Ft%3D33&t=0").unwrap();
    assert_eq!(request.video.unwrap().start_time, Some(33.0));
}

#[test]
fn incoming_watch_shortcut() {
    let request = parse_incoming("viewtube://watch?v=dQw4w9WgXcQ&t=1m").unwrap();
    assert_eq!(request.video, Some(vref("dQw4w9WgXcQ").with_start_time(Some(60.0))));
    assert_eq!(request.mode, Youtube);
    assert_eq!(parse_incoming("viewtube://watch?v=dQw4w9WgXcQ&mode=music").unwrap().mode, Music);
}

#[test]
fn incoming_prefixed_http_link() {
    assert_eq!(parse_incoming("viewtube://https://youtu.be/dQw4w9WgXcQ").unwrap().video.unwrap().video_id, "dQw4w9WgXcQ");
}

#[test]
fn incoming_plain_youtube_links() {
    assert_eq!(parse_incoming("https://youtu.be/dQw4w9WgXcQ").unwrap().video.unwrap().video_id, "dQw4w9WgXcQ");
    let playlist = parse_incoming("https://m.youtube.com/playlist?list=PL1").unwrap();
    assert_eq!(playlist.video, None);
    assert_eq!(playlist.url, "https://www.youtube.com/playlist?list=PL1");
    assert_eq!(parse_incoming("https://music.youtube.com/playlist?list=PL1").unwrap().mode, Music);
}

#[test]
fn incoming_rejects_other_sites() {
    for u in [
        "https://example.com/watch?v=dQw4w9WgXcQ",
        "viewtube://open?url=https%3A%2F%2Fevil.com",
        "viewtube://open",
        "ftp://youtube.com/watch?v=dQw4w9WgXcQ",
    ] {
        assert_eq!(parse_incoming(u), None, "{u}");
    }
}

#[test]
fn incoming_parses_free_text() {
    assert_eq!(parse_incoming_text("  https://youtu.be/dQw4w9WgXcQ \n").unwrap().video.unwrap().video_id, "dQw4w9WgXcQ");
    assert_eq!(parse_incoming_text("youtube.com/watch?v=dQw4w9WgXcQ").unwrap().video.unwrap().video_id, "dQw4w9WgXcQ");
    assert_eq!(parse_incoming_text("lofi hip hop"), None);
}

// MARK: PlayerModeTests

#[test]
fn player_mode_from_host() {
    assert_eq!(PlayerMode::from_host(Some("music.youtube.com")), Some(Music));
    assert_eq!(PlayerMode::from_host(Some("www.youtube.com")), Some(Youtube));
    assert_eq!(PlayerMode::from_host(Some("youtu.be")), Some(Youtube));
    assert_eq!(PlayerMode::from_host(Some("accounts.google.com")), None);
    assert_eq!(PlayerMode::from_host(None), None);
}

#[test]
fn player_mode_other_and_home() {
    assert_eq!(Youtube.other(), Music);
    assert_eq!(Music.other(), Youtube);
    assert_eq!(Music.home_url(), "https://music.youtube.com/");
}

#[test]
fn player_mode_search_urls() {
    assert_eq!(Youtube.search_url(" lofi & chill "), "https://www.youtube.com/results?search_query=lofi%20%26%20chill");
    assert_eq!(Music.search_url("daft punk"), "https://music.youtube.com/search?q=daft%20punk");
}

#[test]
fn player_mode_navigation_policy() {
    for link in [
        "https://www.youtube.com/",
        "https://music.youtube.com/watch?v=x",
        "https://accounts.google.com/signin",
        "https://accounts.google.com.br/x",
        "https://consent.youtube.com/",
        "about:blank",
    ] {
        assert_eq!(navigation::external_target(link), None, "{link}");
    }
    assert_eq!(navigation::external_target("https://github.com").as_deref(), Some("https://github.com"));
    assert_eq!(navigation::external_target("mailto:a@b.c").as_deref(), Some("mailto:a@b.c"));
    assert!(navigation::external_target("https://youtube.com.evil.net/").is_some());
}

#[test]
fn player_mode_youtube_redirect_opens_target_outside() {
    let url = "https://www.youtube.com/redirect?event=video_description&q=https%3A%2F%2Fexample.com%2Fpage";
    assert_eq!(navigation::external_target(url).as_deref(), Some("https://example.com/page"));
}

// MARK: TimeParamTests

#[test]
fn time_param_plain_seconds() {
    assert_eq!(time_param::parse("90"), Some(90.0));
    assert_eq!(time_param::parse("90s"), Some(90.0));
    assert_eq!(time_param::parse("12.5"), Some(12.5));
}

#[test]
fn time_param_units() {
    assert_eq!(time_param::parse("1m30s"), Some(90.0));
    assert_eq!(time_param::parse("1h2m3s"), Some(3723.0));
    assert_eq!(time_param::parse("2m"), Some(120.0));
}

#[test]
fn time_param_clock() {
    assert_eq!(time_param::parse("1:30"), Some(90.0));
    assert_eq!(time_param::parse("1:02:03"), Some(3723.0));
}

#[test]
fn time_param_invalid() {
    for t in ["", "abc", "1x", "-5", "1:2:3:4"] {
        assert_eq!(time_param::parse(t), None, "{t}");
    }
}

// MARK: RemoteCommandTests

#[test]
fn remote_playback_commands() {
    assert_eq!(RemoteCommand::parse("viewtube://play"), Some(RemoteCommand::Play));
    assert_eq!(RemoteCommand::parse("viewtube://pause"), Some(RemoteCommand::Pause));
    assert_eq!(RemoteCommand::parse("viewtube://toggle"), Some(RemoteCommand::Toggle));
    assert_eq!(RemoteCommand::parse("viewtube://next"), Some(RemoteCommand::Next));
    assert_eq!(RemoteCommand::parse("viewtube://prev"), Some(RemoteCommand::Previous));
    assert_eq!(RemoteCommand::parse("viewtube://browser"), Some(RemoteCommand::OpenInBrowser));
}

#[test]
fn remote_mode_commands() {
    assert_eq!(RemoteCommand::parse("viewtube://mode/music"), Some(RemoteCommand::Mode(Some(Music))));
    assert_eq!(RemoteCommand::parse("viewtube://mode/youtube"), Some(RemoteCommand::Mode(Some(Youtube))));
    assert_eq!(RemoteCommand::parse("viewtube://mode"), Some(RemoteCommand::Mode(None)));
    assert_eq!(RemoteCommand::parse("viewtube://mode/toggle"), Some(RemoteCommand::Mode(None)));
    assert_eq!(RemoteCommand::parse("viewtube://mode/tiktok"), None);
}

#[test]
fn remote_speed_command() {
    assert_eq!(RemoteCommand::parse("viewtube://speed/1.5"), Some(RemoteCommand::Speed(1.5)));
    assert_eq!(RemoteCommand::parse("viewtube://speed/2"), Some(RemoteCommand::Speed(2.0)));
    assert_eq!(RemoteCommand::parse("viewtube://speed/10"), None);
    assert_eq!(RemoteCommand::parse("viewtube://speed/inf"), None);
    assert_eq!(RemoteCommand::parse("viewtube://speed"), None);
}

#[test]
fn remote_ignores_links_and_other_schemes() {
    assert_eq!(RemoteCommand::parse("viewtube://open?url=x"), None);
    assert_eq!(RemoteCommand::parse("https://play"), None);
}

// MARK: BookmarkletAndPolicyTests

#[test]
fn bookmarklet_sends_link_and_time_to_app() {
    assert!(BOOKMARKLET.starts_with("javascript:"));
    assert!(BOOKMARKLET.contains("viewtube://open?url="));
    assert!(BOOKMARKLET.contains("v.pause()"));
    assert!(!BOOKMARKLET.contains('\n'));
    // Byte a byte igual ao do Swift.
    assert_eq!(
        BOOKMARKLET,
        "javascript:(()=>{const v=document.querySelector('video');const t=v?Math.floor(v.currentTime):0;if(v)v.pause();location.href='viewtube://open?url='+encodeURIComponent(location.href)+'&t='+t;})()"
    );
}

#[test]
fn regional_google_prefix_needs_country_suffix() {
    assert_eq!(navigation::external_target("https://consent.google.de/"), None);
    assert!(navigation::external_target("https://accounts.google.evil.com/").is_some());
    assert!(navigation::external_target("https://accounts.google.phish/").is_some());
}

#[test]
fn forced_mode_does_not_allow_other_sites() {
    assert_eq!(parse_incoming("viewtube://open?url=https%3A%2F%2Fevil.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&mode=music"), None);
}

// MARK: ClipboardOfferTests

#[test]
fn clipboard_offers_new_youtube_link() {
    let offer = ClipboardOffer::evaluate("https://youtu.be/dQw4w9WgXcQ?t=42", Some("other000000")).unwrap();
    assert_eq!(offer.request.video.unwrap().video_id, "dQw4w9WgXcQ");
    assert_eq!(offer.label, "youtu.be/dQw4w9WgXcQ");
}

#[test]
fn clipboard_ignores_link_already_playing() {
    assert_eq!(ClipboardOffer::evaluate("https://www.youtube.com/watch?v=dQw4w9WgXcQ", Some("dQw4w9WgXcQ")), None);
}

#[test]
fn clipboard_ignores_text_and_other_sites() {
    assert_eq!(ClipboardOffer::evaluate("hello world", None), None);
    assert_eq!(ClipboardOffer::evaluate("https://example.com/watch?v=dQw4w9WgXcQ", None), None);
    assert_eq!(ClipboardOffer::evaluate(&"a".repeat(5000), None), None);
}

#[test]
fn clipboard_labels_playlists_and_music_links() {
    let playlist = ClipboardOffer::evaluate("https://www.youtube.com/playlist?list=PL123", None).unwrap();
    assert_eq!(playlist.label, "youtube.com/playlist");
    let music = ClipboardOffer::evaluate("https://music.youtube.com/watch?v=dQw4w9WgXcQ", None).unwrap();
    assert_eq!(music.request.mode, Music);
    assert_eq!(music.label, "music.youtube.com/dQw4w9WgXcQ");
}

// MARK: PrefCookieTests

#[test]
fn pref_reads_language_country_and_restricted_mode() {
    let pref = PrefCookie::parse("f6=40000000&tz=America.Sao_Paulo&hl=pt&gl=BR&f2=8000000");
    assert_eq!(pref.language(), Some("pt"));
    assert_eq!(pref.country(), Some("BR"));
    assert!(pref.restricted());
    assert!(!PrefCookie::parse("f6=40000000").restricted());
}

#[test]
fn pref_changes_keep_other_fields_and_order() {
    let pref = PrefCookie::parse("f6=40000000&hl=pt&tz=UTC");
    assert_eq!(pref.setting("hl", Some("en")).raw(), "f6=40000000&hl=en&tz=UTC");
    assert_eq!(pref.setting("gl", Some("PT")).raw(), "f6=40000000&hl=pt&tz=UTC&gl=PT");
    assert_eq!(pref.setting("hl", None).raw(), "f6=40000000&tz=UTC");
}

#[test]
fn pref_restricted_mode_only_touches_its_bit() {
    let on = PrefCookie::parse("f2=100&hl=pt").with_restricted(true);
    assert_eq!(on.get("f2"), Some("8000100"));
    assert!(on.restricted());
    assert_eq!(on.with_restricted(false).get("f2"), Some("100"));
    assert_eq!(PrefCookie::parse("f2=8000000").with_restricted(false).get("f2"), None);
}

// MARK: SponsorBlockTests

#[test]
fn sponsorblock_hash_prefix_is_first_four_hex_of_sha256() {
    assert_eq!(sponsorblock::hash_prefix("dQw4w9WgXcQ"), "5f6b");
}

#[test]
fn sponsorblock_request_url_carries_categories_and_skip_action() {
    let url = url::Url::parse(&sponsorblock::request_url("dQw4w9WgXcQ", &["sponsor", "intro"])).unwrap();
    assert_eq!(url.host_str(), Some("sponsor.ajay.app"));
    assert_eq!(url.path(), "/api/skipSegments/5f6b");
    let items: std::collections::HashMap<_, _> = url.query_pairs().into_owned().collect();
    assert_eq!(items["categories"], r#"["sponsor","intro"]"#);
    assert_eq!(items["actionTypes"], r#"["skip"]"#);
}

#[test]
fn sponsorblock_decode_keeps_only_matching_video_and_skip_segments() {
    let json = r#"
    [
      {"videoID": "other000000", "segments": [{"category": "sponsor", "actionType": "skip", "segment": [1, 2]}]},
      {"videoID": "dQw4w9WgXcQ", "segments": [
        {"category": "intro", "actionType": "skip", "segment": [30.5, 40]},
        {"category": "sponsor", "actionType": "skip", "segment": [0, 12.25]},
        {"category": "poi_highlight", "actionType": "poi", "segment": [50, 50]},
        {"category": "sponsor", "actionType": "skip", "segment": [9, 8]}
      ]}
    ]"#;
    let segments = sponsorblock::decode_segments(json, "dQw4w9WgXcQ").unwrap();
    assert_eq!(
        segments,
        vec![
            sponsorblock::Segment { start: 0.0, end: 12.25, category: "sponsor".into() },
            sponsorblock::Segment { start: 30.5, end: 40.0, category: "intro".into() },
        ]
    );
}

#[test]
fn sponsorblock_decode_rejects_garbage() {
    assert!(sponsorblock::decode_segments("nope", "x").is_err());
}

#[test]
fn sponsorblock_default_categories_match_pear_defaults() {
    let mut cats = sponsorblock::DEFAULT_CATEGORIES.to_vec();
    cats.sort();
    assert_eq!(cats, ["interaction", "intro", "music_offtopic", "outro", "selfpromo", "sponsor"]);
}

// MARK: LyricsTests

fn line(time: f64, text: &str) -> Line {
    Line { time, text: text.into() }
}

#[test]
fn lrc_parses_timestamps_and_sorts_lines() {
    let lrc = "[ar:Queen]\n[00:12.50]Is this the real life?\n[00:05.00]Intro\n[01:02.123][01:30.00]Repeated\n[00:20.00]\nnot a lyric line";
    assert_eq!(
        lyrics::parse_lrc(lrc),
        vec![
            line(5.0, "Intro"),
            line(12.5, "Is this the real life?"),
            line(20.0, ""),
            line(62.123, "Repeated"),
            line(90.0, "Repeated"),
        ]
    );
}

#[test]
fn lrc_applies_offset_tag() {
    assert_eq!(lyrics::parse_lrc("[offset:+500]\n[00:10.00]A")[0].time, 9.5);
}

#[test]
fn lrc_empty_or_garbage() {
    assert_eq!(lyrics::parse_lrc(""), vec![]);
    assert_eq!(lyrics::parse_lrc("[xx:yy]oops"), vec![]);
}

#[test]
fn lyrics_cleans_titles_for_search() {
    assert_eq!(lyrics::clean_title("Bohemian Rhapsody (Live At Wembley Stadium / Saturday 12th July 1986)"), "Bohemian Rhapsody");
    assert_eq!(lyrics::clean_title("Song Name [Official Music Video]"), "Song Name");
    assert_eq!(lyrics::clean_title("Song - Remastered 2011"), "Song");
    assert_eq!(lyrics::clean_title("Plain"), "Plain");
    assert_eq!(lyrics::primary_artist("Daft Punk & Pharrell Williams"), "Daft Punk");
    assert_eq!(lyrics::primary_artist("A, B e C"), "A");
}

#[test]
fn lyrics_builds_get_and_search_urls() {
    let get = url::Url::parse(&lyrics::lrclib_get_url("Song", "Artist", "Album", 200.7)).unwrap();
    assert_eq!(get.host_str(), Some("lrclib.net"));
    assert_eq!(get.path(), "/api/get");
    let items: Vec<(String, String)> = get.query_pairs().into_owned().collect();
    assert!(items.contains(&("duration".into(), "201".into())));
    assert!(items.contains(&("album_name".into(), "Album".into())));
    let search = lyrics::lrclib_search_url("Song & More", "Artist");
    assert!(search.contains("/api/search?"));
    assert!(search.contains("track_name=Song%20%26%20More"));
}

#[test]
fn lyrics_picks_synced_result_with_closest_duration() {
    let json = r#"[
      {"duration": 300, "syncedLyrics": "[00:01.00]far\n[00:02.00]b\n[00:03.00]c\n[00:04.00]d", "plainLyrics": "far", "instrumental": false},
      {"duration": 202, "syncedLyrics": null, "plainLyrics": "plain only\nb\nc\nd", "instrumental": false},
      {"duration": 199, "syncedLyrics": "[00:01.00]close\n[00:02.00]b\n[00:03.00]c\n[00:04.00]d", "plainLyrics": "close\nb\nc\nd", "instrumental": false}
    ]"#;
    let result = lyrics::best_lrclib_match(json, 200.0).unwrap().unwrap();
    assert_eq!(result.lines[0].text, "close");
}

#[test]
fn lyrics_synced_from_another_version_becomes_plain_text() {
    let json = r#"[{"duration": 206, "syncedLyrics": "[00:01.00]a\n[00:02.00]b\n[00:03.00]c\n[00:04.00]d", "plainLyrics": "a\nb\nc\nd", "instrumental": false}]"#;
    let result = lyrics::best_lrclib_match(json, 200.0).unwrap().unwrap();
    assert_eq!(result.lines, vec![]);
    assert_eq!(result.plain, "a\nb\nc\nd");
}

#[test]
fn lyrics_synced_within_two_seconds_stays_synced() {
    let json = r#"[{"duration": 201.5, "syncedLyrics": "[00:01.00]a\n[00:02.00]b\n[00:03.00]c\n[00:04.00]d", "plainLyrics": "a\nb\nc\nd", "instrumental": false}]"#;
    assert_eq!(lyrics::best_lrclib_match(json, 200.0).unwrap().unwrap().lines.len(), 4);
}

#[test]
fn lyrics_falls_back_to_plain_and_skips_far_durations() {
    let plain = r#"[{"duration": 203, "syncedLyrics": null, "plainLyrics": "only words\nb\nc\nd", "instrumental": false}]"#;
    assert_eq!(lyrics::best_lrclib_match(plain, 200.0).unwrap().unwrap().plain, "only words\nb\nc\nd");
    let far = r#"[{"duration": 400, "syncedLyrics": "[00:01.00]x\n[00:02.00]b\n[00:03.00]c\n[00:04.00]d", "plainLyrics": "x", "instrumental": false}]"#;
    assert_eq!(lyrics::best_lrclib_match(far, 200.0).unwrap(), None);
}

#[test]
fn lyrics_rejects_junk_entries() {
    let junk = r#"{"duration": 213, "syncedLyrics": "[00:01.00]probe", "plainLyrics": "probe", "instrumental": false}"#;
    assert_eq!(lyrics::decode_lrclib_get(junk).unwrap(), None);
}

#[test]
fn lyrics_decodes_single_get_response() {
    let json = r#"{"duration": 200, "syncedLyrics": "[00:02.00]a\n[00:03.00]b\n[00:04.00]c\n[00:05.00]d", "plainLyrics": "a\nb\nc\nd", "instrumental": false}"#;
    assert_eq!(lyrics::decode_lrclib_get(json).unwrap().unwrap().lines[0], line(2.0, "a"));
    let instrumental = r#"{"duration": 200, "syncedLyrics": null, "plainLyrics": null, "instrumental": true}"#;
    assert_eq!(lyrics::decode_lrclib_get(instrumental).unwrap(), None);
}

// MARK: YouTubeMusicLyricsTests

#[test]
fn ytm_finds_lyrics_browse_id_in_next_response() {
    let json = r#"{"contents":{"tabs":[{"tabRenderer":{"endpoint":{"browseEndpoint":{"browseId":"FEmusic_x"}}}},{"tabRenderer":{"endpoint":{"browseEndpoint":{"browseId":"MPLYt_abc123"}}}}]}}"#;
    assert_eq!(lyrics::ytm_lyrics_browse_id(json).as_deref(), Some("MPLYt_abc123"));
    assert_eq!(lyrics::ytm_lyrics_browse_id(r#"{"contents":{}}"#), None);
}

#[test]
fn ytm_timed_lyrics_become_synced_lines() {
    let json = r#"{"contents":{"x":{"timedLyricsModel":{"lyricsData":{"sourceMessage":"Fonte: Musixmatch","timedLyricsData":[
      {"lyricLine":"♪","cueRange":{"startTimeMilliseconds":"0"}},
      {"lyricLine":"Primeira","cueRange":{"startTimeMilliseconds":"14840"}},
      {"lyricLine":"Segunda","cueRange":{"startTimeMilliseconds":"20180"}},
      {"lyricLine":"Terceira","cueRange":{"startTimeMilliseconds":"25000"}},
      {"lyricLine":"Quarta","cueRange":{"startTimeMilliseconds":"30500"}}
    ]}}}}}"#;
    let result = lyrics::ytm_result(json).unwrap();
    assert_eq!(result.lines.len(), 5);
    assert_eq!(result.lines[1], line(14.84, "Primeira"));
    assert_eq!(result.source, "Musixmatch");
}

#[test]
fn ytm_lyrics_without_times_are_plain_text() {
    let json = r#"{"timedLyricsData":[{"lyricLine":"a"},{"lyricLine":"b"},{"lyricLine":"c"},{"lyricLine":"d"}],"sourceMessage":"Fonte: Musixmatch"}"#;
    let result = lyrics::ytm_result(json).unwrap();
    assert_eq!(result.lines, vec![]);
    assert_eq!(result.plain, "a\nb\nc\nd");
}

#[test]
fn ytm_no_lyrics_gives_none() {
    assert_eq!(lyrics::ytm_result(r#"{"contents":{}}"#), None);
}

// MARK: WebAssetTests

#[test]
fn web_asset_expands_css_marker_as_js_string() {
    let out = web_asset::expand("s.textContent = __VT_CSS(a-b.css)__;", |name| {
        assert_eq!(name, "a-b.css");
        Ok("p { content: \"x\"; }\n".into())
    })
    .unwrap();
    assert_eq!(out, r#"s.textContent = "p { content: \"x\"; }\n";"#);
}

#[test]
fn web_asset_ignores_names_that_could_leave_the_folder() {
    let script = "__VT_CSS(../x.css)__ __VT_CSS(A.css)__";
    assert_eq!(web_asset::expand(script, |_| panic!("não devia ler")).unwrap(), script);
}

#[test]
fn web_asset_missing_css_fails() {
    assert!(web_asset::expand("__VT_CSS(nada.css)__", |n| Err(web_asset::Failure::Missing(n.into()))).is_err());
}

#[test]
fn web_asset_shared_folder_is_complete() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../web");
    let scripts = viewtube_core::PageScripts::load(&dir).unwrap();
    assert_eq!(scripts.document_start.len() + scripts.document_end.len() + 1, 15);
    for s in scripts.document_start.iter().chain(&scripts.document_end).chain([&scripts.page_flags]) {
        assert!(!s.contains("__VT_CSS("));
        assert!(!s.is_empty());
    }
}

#[test]
fn page_config_json_uses_swift_field_names() {
    let json: serde_json::Value = serde_json::from_str(&viewtube_core::PageConfig::default().json()).unwrap();
    let mut keys: Vec<&str> = json.as_object().unwrap().keys().map(String::as_str).collect();
    keys.sort();
    assert_eq!(
        keys,
        [
            "blockAds", "clean", "cover", "hideFullscreenChat", "home", "lyrics", "musicRate", "muted", "portrait",
            "portraitZoom", "quality", "sponsorBlock", "theater", "videoRate", "volume"
        ]
    );
}
