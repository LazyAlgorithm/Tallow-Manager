using System;
using System.Collections;
using System.IO;
using Tallow;

namespace TallowManager;

/// One release of a game or the engine on GitHub, with the file for this platform.
class Release
{
	public String tag = new .() ~ delete _;
	public String name = new .() ~ delete _;
	/// "2026-10-13".
	public String date = new .() ~ delete _;
	/// Marked as a pre-release on GitHub: shown as a beta.
	public bool beta;
	public String notes = new .() ~ delete _;
	public String assetUrl = new .() ~ delete _;
	public int64 assetSize;
	/// The release's SHA256SUMS file, if it has one.
	public String sumsUrl = new .() ~ delete _;

	public void CopyTo(Release other)
	{
		other.tag.Set(tag);
		other.name.Set(name);
		other.date.Set(date);
		other.beta = beta;
		other.notes.Set(notes);
		other.assetUrl.Set(assetUrl);
		other.assetSize = assetSize;
		other.sumsUrl.Set(sumsUrl);
	}
}

/// Asks GitHub for releases. Public repositories need no account; GitHub allows 60 questions an hour from one
/// address, so the Hub asks once when it starts and when Check for Updates is pressed.
static class Releases
{
	/// The newest release of item that has a file for this platform. With betas false, pre-releases are passed over.
	public static bool Latest(Catalog.Item item, bool betas, Release result, String error)
	{
		let results = scope List<Release>();
		defer { ClearAndDeleteItems!(results); }
		if (!All(item, betas, 1, results, error))
			return false;
		results[0].CopyTo(result);
		return true;
	}

	/// Up to limit releases of item that have a file for this platform, newest first. False if there are none.
	public static bool All(Catalog.Item item, bool betas, int limit, List<Release> results, String error)
	{
		let text = scope String();
		if (!Http.GetText(scope $"https://api.github.com/repos/{item.repo}/releases?per_page=30", text, error))
			return false;
		let root = SaveNode.FromText(text);
		defer delete root;
		if (root == null || root.kind != .List)
		{
			// GitHub answers with an object when it refuses: {"message": "API rate limit exceeded ..."}.
			let message = root?["message"];
			error.Set(message != null && message.kind == .String ? message.text : "GitHub sent an answer the Hub does not understand.");
			return false;
		}
		for (let release in root.items)
		{
			if (results.Count >= limit)
				break;
			let result = new Release();
			if (Read(item, betas, release, result))
				results.Add(result);
			else
				delete result;
		}
		if (results.IsEmpty)
		{
			error.Set(betas ? "There is no release for this computer yet." : "There is no release for this computer yet that is not a beta.");
			return false;
		}
		return true;
	}

	/// The newest perSeries releases of each version series ("v0.1.x", "v0.2.x"...) that have a file for this
	/// platform: the series newest first, each newest first. Reads up to three pages of 100, so that an older series
	/// stays listed while a newer one is released often. False if there are none.
	public static bool BySeries(Catalog.Item item, bool betas, int perSeries, List<Release> results, String error)
	{
		Dictionary<String, int> counts = scope .();
		defer
		{
			for (let key in counts.Keys)
				delete key;
		}
		for (int page = 1; page <= 3; page++)
		{
			let text = scope String();
			if (!Http.GetText(scope $"https://api.github.com/repos/{item.repo}/releases?per_page=100&page={page}" , text, error))
			{
				if (page == 1)
					return false;
				break;
			}
			let root = SaveNode.FromText(text);
			defer delete root;
			if (root == null || root.kind != .List)
			{
				if (page > 1)
					break;
				let message = root?["message"];
				error.Set(message != null && message.kind == .String ? message.text : "GitHub sent an answer the Hub does not understand.");
				return false;
			}
			for (let release in root.items)
			{
				let result = new Release();
				if (!Read(item, betas, release, result))
				{
					delete result;
					continue;
				}
				let series = Series(result.tag, .. scope .());
				if (counts.TryGetValue(series, let count))
				{
					if (count >= perSeries)
					{
						delete result;
						continue;
					}
					counts[series] = count + 1;
				}
				else
					counts[new .(series)] = 1;
				results.Add(result);
			}
			if (root.items.Count < 100)
				break;
		}
		if (results.IsEmpty)
		{
			error.Set(betas ? "There is no release for this computer yet." : "There is no release for this computer yet that is not a beta.");
			return false;
		}
		results.Sort(scope (a, b) => CompareVersions(b.tag, a.tag));
		return true;
	}

	/// "v0.2.14-beta" is in series "0.2"; a tag without a version is a series of its own.
	public static void Series(StringView tag, String output)
	{
		int[3] parts = default;
		if (Parts(tag, ref parts) < 2)
		{
			output.Set(tag);
			return;
		}
		output.AppendF("{}.{}", parts[0], parts[1]);
	}

	/// Compares two tags by their version numbers (v0.2.3 is newer than v0.1.52); tags without one sort by text.
	public static int CompareVersions(StringView a, StringView b)
	{
		int[3] left = default, right = default;
		let leftCount = Parts(a, ref left), rightCount = Parts(b, ref right);
		if (leftCount == 0 || rightCount == 0)
			return leftCount != rightCount ? leftCount <=> rightCount : a.CompareTo(b);
		for (int i < 3)
		{
			if (left[i] != right[i])
				return left[i] <=> right[i];
		}
		return 0;
	}

	/// Reads up to three dot-separated numbers after an optional "v"; returns how many.
	static int Parts(StringView tag, ref int[3] parts)
	{
		var text = tag;
		if (text.StartsWith('v') || text.StartsWith('V'))
			text = text.Substring(1);
		int count = 0, i = 0;
		while (count < 3 && i < text.Length && text[i].IsDigit)
		{
			int value = 0;
			while (i < text.Length && text[i].IsDigit)
				value = value * 10 + ((int)text[i++] - (int)'0');
			parts[count++] = value;
			if (i < text.Length && text[i] == '.')
				i++;
			else
				break;
		}
		return count;
	}

	static bool Read(Catalog.Item item, bool betas, SaveNode release, Release result)
	{
		if (Flag(release, "draft"))
			return false;
		let tag = Text(release, "tag_name");
		if (!item.tagPrefix.IsEmpty && !tag.StartsWith(item.tagPrefix))
			return false;
		let prerelease = Flag(release, "prerelease");
		if (prerelease && !betas)
			return false;
		let assets = release["assets"];
		if (assets == null)
			return false;
		bool found = false;
		for (let asset in assets.items)
		{
			let name = Text(asset, "name");
			if (name == item.asset)
			{
				result.assetUrl.Set(Text(asset, "browser_download_url"));
				let size = asset["size"];
				result.assetSize = size != null ? size.AsInteger : 0;
				found = true;
			}
			else if (name.StartsWith("SHA256SUMS"))
				result.sumsUrl.Set(Text(asset, "browser_download_url"));
		}
		if (!found)
			return false;
		result.tag.Set(tag);
		result.name.Set(Text(release, "name"));
		if (result.name.IsEmpty)
			result.name.Set(tag);
		result.beta = prerelease;
		result.notes.Set(Text(release, "body"));
		let published = Text(release, "published_at");
		result.date.Set(published.Length >= 10 ? published.Substring(0, 10) : published);
		return true;
	}

	/// Checks a downloaded file against the release's SHA256SUMS. True if it matches, or the release has no sums.
	public static bool Verify(Release release, StringView file, StringView assetName, String error)
	{
		if (release.sumsUrl.IsEmpty)
			return true;
		let sums = scope String();
		if (!Http.GetText(release.sumsUrl, sums, error))
			return false;
		let actual = scope String();
		if (!Task.HashFile(file, actual))
		{
			error.Set("Could not read the downloaded file.");
			return false;
		}
		for (var line in sums.Split('\n'))
		{
			line.Trim();
			// "<hash>  <name>" (or " *<name>" from a binary-mode sum).
			let space = line.IndexOf(' ');
			if (space < 0)
				continue;
			var name = line.Substring(space + 1);
			name.Trim();
			if (name.StartsWith('*'))
				name.RemoveFromStart(1);
			if (name != assetName)
				continue;
			let expected = scope String(line.Substring(0, space));
			expected.ToLower();
			if (expected == actual)
				return true;
			error.Set("The download is damaged (its checksum does not match). Try again.");
			return false;
		}
		// Sums for the other files only: nothing to check this one against.
		return true;
	}

	static StringView Text(SaveNode node, StringView key)
	{
		let value = node[key];
		return value != null && value.kind == .String ? value.text : "";
	}

	static bool Flag(SaveNode node, StringView key)
	{
		let value = node[key];
		return value != null && value.kind == .Bool && value.integer != 0;
	}
}
