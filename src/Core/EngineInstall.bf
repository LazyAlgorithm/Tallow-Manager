using System;
using System.IO;
using Tallow;

namespace TallowManager;

/// Native, side-by-side engine installation. No Python or existing engine required.
/// Caller must choose a release explicitly; this class never performs auto-updates.
static class EngineInstall
{
	/// Install a selected official release using Hub's downloader, SHA-256 and unpacker.
	/// The release must publish SHA256SUMS, unlike optional checks for game packages.
	public static bool Install(Task task, Release release, StringView assetName, StringView versionsRoot)
	{
		if (release.assetUrl.IsEmpty || release.sumsUrl.IsEmpty)
			return task.Fail("Engine releases must provide an archive and SHA256SUMS.");
		if (assetName.IsEmpty || assetName.Contains('/') || assetName.Contains('\\'))
			return task.Fail("Invalid engine archive name.");

		let staging = scope $"{versionsRoot}/.installing-{DateTime.Now.Ticks}";
		let archive = scope $"{staging}/{assetName}";
		let unpacked = scope $"{staging}/unpacked";
		Directory.CreateDirectory(staging).IgnoreError();
		defer Directory.Delete(staging, true).IgnoreError();

		if (!task.Download(release.assetUrl, archive, "Downloading Tallow engine"))
			return false;
		let error = scope String();
		if (!VerifyRequiredChecksum(release, archive, assetName, error))
			return task.Fail(error);
		if (!task.Unpack(archive, unpacked, "Extracting Tallow engine"))
			return false;

		let manifestPath = scope $"{unpacked}/tessera-version.json";
		let manifestText = scope String();
		if (File.ReadAllText(manifestPath, manifestText) case .Err)
			return task.Fail("Engine package has no tessera-version.json.");
		let manifest = SaveNode.FromText(manifestText);
		defer delete manifest;
		if (manifest == null || manifest.kind != .Object)
			return task.Fail("Invalid engine identity manifest.");
		let engine = manifest["engine"];
		let version = manifest["version"];
		let build = manifest["build"];
		if (engine == null || engine.kind != .String || engine.text != "Tallow" ||
			version == null || version.kind != .String ||
			build == null || build.kind != .String ||
			!SafeVersion(version.text) || !ValidCommit(build.text))
			return task.Fail("Invalid engine version or immutable build identity.");

		// Never accept an archive whose identity conflicts with the selected release.
		if (!release.tag.Contains(version.text) && !release.tag.Contains(build.text))
			return task.Fail("Engine package identity does not match the selected release.");
		let destination = scope $"{versionsRoot}/versions/{version.text}/{build.text}";
		if (Directory.Exists(destination))
			return task.Fail("This exact engine build is already installed.");
		if (!File.Exists(scope $"{unpacked}/tessera-version.json") ||
			!Directory.Exists(scope $"{unpacked}/Engine") ||
			!Directory.Exists(scope $"{unpacked}/Editor"))
			return task.Fail("Incomplete engine package.");
		Directory.CreateDirectory(scope $"{versionsRoot}/versions/{version.text}").IgnoreError();
		task.SetStatus("Installing verified engine version", -1);
		if (task.Cancelled)
			return task.Fail("Cancelled.");
		if (Directory.Move(unpacked, destination) case .Err)
			return task.Fail("Could not finalize engine installation.");
		return true;
	}

	static bool SafeVersion(StringView value)
	{
		if (value.IsEmpty || value.Length > 100 || value == "." || value == "..")
			return false;
		for (let c in value)
			if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) && c != '.' && c != '-' && c != '+')
				return false;
		return (value[0] >= 'a' && value[0] <= 'z') || (value[0] >= 'A' && value[0] <= 'Z') || (value[0] >= '0' && value[0] <= '9');
	}

	static bool ValidCommit(StringView value)
	{
		if (value.Length != 40)
			return false;
		for (let c in value)
			if (!(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f'))
				return false;
		return true;
	}

	/// Require a matching checksum entry, unlike the optional game checksum path.
	static bool VerifyRequiredChecksum(Release release, StringView archive, StringView assetName, String error)
	{
		let sums = scope String();
		if (!Http.GetText(release.sumsUrl, sums, error))
			return false;
		let actual = scope String();
		if (!Task.HashFile(archive, actual))
		{
			error.Set("Unable to hash the engine archive.");
			return false;
		}
		for (var line in sums.Split('\n'))
		{
			line.Trim();
			let separator = line.IndexOf(' ');
			if (separator < 0)
				continue;
			var name = line.Substring(separator + 1);
			name.Trim();
			if (name.StartsWith('*'))
				name.RemoveFromStart(1);
			if (name != assetName)
				continue;
			let expected = scope String(line.Substring(0, separator));
			expected.ToLower();
			if (expected == actual)
				return true;
			error.Set("Engine archive SHA-256 mismatch.");
			return false;
		}
		error.Set("Engine release checksum file does not list this archive.");
		return false;
	}
}
