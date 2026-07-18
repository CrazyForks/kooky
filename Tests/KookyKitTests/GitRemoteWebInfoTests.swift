import XCTest
@testable import KookyKit

final class GitRemoteWebInfoTests: XCTestCase {
    private func parse(_ raw: String) -> GitRemoteWebInfo? {
        GitRemoteWebInfo.parse(remoteURL: raw)
    }

    // MARK: - URL shapes

    func testScpLikeSSH() {
        let info = parse("git@github.com:corey/kookycode.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://github.com/corey/kookycode")
        XCTAssertEqual(info?.host, "github.com")
    }

    func testScpLikeWithoutUser() {
        let info = parse("github.com:corey/kookycode.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://github.com/corey/kookycode")
    }

    func testSSHScheme() {
        let info = parse("ssh://git@github.com/corey/kookycode.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://github.com/corey/kookycode")
    }

    func testSSHSchemeWithPortDropsPort() {
        let info = parse("ssh://git@git.company.com:2222/team/repo.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://git.company.com/team/repo")
    }

    func testHTTPS() {
        let info = parse("https://github.com/corey/kookycode.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://github.com/corey/kookycode")
    }

    func testHTTPSWithoutDotGit() {
        let info = parse("https://github.com/corey/kookycode")
        XCTAssertEqual(info?.webURL.absoluteString, "https://github.com/corey/kookycode")
    }

    func testHTTPSWithPortKeepsPort() {
        // Unlike an ssh port, an https remote's port IS the web port.
        let info = parse("https://gitlab.example.com:8443/group/repo.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://gitlab.example.com:8443/group/repo")
    }

    func testHTTPRemoteKeepsScheme() {
        // An http-only internal forge has no https side to rewrite to.
        let info = parse("http://git.internal/team/repo.git")
        XCTAssertEqual(info?.webURL.absoluteString, "http://git.internal/team/repo")
    }

    func testGitScheme() {
        let info = parse("git://github.com/corey/kookycode.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://github.com/corey/kookycode")
    }

    func testTrailingSlashStripped() {
        let info = parse("https://github.com/corey/kookycode/")
        XCTAssertEqual(info?.webURL.absoluteString, "https://github.com/corey/kookycode")
    }

    func testNestedGroupPathSurvives() {
        // GitLab subgroups nest arbitrarily deep — the whole path is the repo id.
        let info = parse("git@gitlab.com:group/subgroup/repo.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://gitlab.com/group/subgroup/repo")
    }

    // MARK: - Non-web remotes rejected

    func testLocalPathRejected() {
        XCTAssertNil(parse("/Users/corey/Github/kookycode"))
        XCTAssertNil(parse("../relative/repo"))
    }

    func testFileSchemeRejected() {
        XCTAssertNil(parse("file:///Users/corey/Github/kookycode"))
    }

    func testEmptyRejected() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("   "))
    }

    func testHostOnlyRejected() {
        // No repo path → nothing to browse.
        XCTAssertNil(parse("git@github.com:"))
    }

    // MARK: - Forge detection

    func testGitHubForge() {
        XCTAssertEqual(parse("git@github.com:corey/kookycode.git")?.forgeName, "GitHub")
    }

    func testGitHubEnterpriseHostDetected() {
        XCTAssertEqual(parse("git@github.company.com:team/repo.git")?.forgeName, "GitHub")
    }

    func testGitLabForge() {
        XCTAssertEqual(parse("git@gitlab.com:group/repo.git")?.forgeName, "GitLab")
    }

    func testBitbucketForge() {
        XCTAssertEqual(parse("git@bitbucket.org:team/repo.git")?.forgeName, "Bitbucket")
    }

    func testUnknownForgeFallsBackToHostName() {
        XCTAssertEqual(parse("git@git.sr.ht:~corey/repo")?.forgeName, "git.sr.ht")
    }

    // MARK: - `git remote -v` listing

    func testRemoteListingPrefersOrigin() {
        let listing = """
        upstream\thttps://github.com/other/fork.git (fetch)
        upstream\thttps://github.com/other/fork.git (push)
        origin\tgit@github.com:corey/kookycode.git (fetch)
        origin\tgit@github.com:corey/kookycode.git (push)
        """
        XCTAssertEqual(
            GitRemoteWebInfo.preferredRemoteURL(inRemoteListing: listing),
            "git@github.com:corey/kookycode.git"
        )
    }

    func testRemoteListingFallsBackToFirstRemote() {
        let listing = """
        upstream\thttps://github.com/other/fork.git (fetch)
        upstream\thttps://github.com/other/fork.git (push)
        """
        XCTAssertEqual(
            GitRemoteWebInfo.preferredRemoteURL(inRemoteListing: listing),
            "https://github.com/other/fork.git"
        )
    }

    func testRemoteListingIgnoresPushOnlyLines() {
        XCTAssertNil(GitRemoteWebInfo.preferredRemoteURL(
            inRemoteListing: "origin\tgit@github.com:corey/kookycode.git (push)"
        ))
    }

    func testEmptyRemoteListing() {
        XCTAssertNil(GitRemoteWebInfo.preferredRemoteURL(inRemoteListing: ""))
    }
}
