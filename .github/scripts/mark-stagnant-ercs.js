// @ts-check
/**
 * Moves ERCs that have gone six months without an edit to Stagnant.
 *
 * Each eligible ERC gets a pull request flipping its status, which is squash
 * merged two weeks later. That delay is the author's notice period: the pull
 * request mentions them, and EIP-1 lets them resurrect the proposal at any time.
 *
 * This replaces ethereum/EIP-Bot, which runs the same process for ethereum/EIPs
 * but looks for proposals in a hardcoded `EIPS/` directory that does not exist
 * here. It was archived in January 2023, so it cannot be fixed upstream.
 */

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const PROPOSALS_DIR = "ERCS";
const DEFAULT_BRANCH = "master";
const STAGNATION_CUTOFF_MONTHS = 6;
const MERGE_DELAY_WEEKS = 2;
const STAGNATABLE_STATUSES = ["draft", "review"];
const STAGNANT = "Stagnant";

/** Identifies this bot's pull requests. Same labels the EIPs bot uses. */
const BOT_LABELS = ["created-by-bot", "1272989785"];

/** Pull requests are rate limited harder than other endpoints, so space them out. */
const WAIT_MS = 5000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const monthsAgo = (months) => {
  const date = new Date();
  date.setMonth(date.getMonth() - months);
  return date;
};

const weeksAgo = (weeks) => {
  const date = new Date();
  date.setDate(date.getDate() - weeks * 7);
  return date;
};

/**
 * Newest commit date for every file under `ERCS/`, from one `git log` pass.
 * The EIPs bot spends an API request per proposal on this; reading the checkout
 * is equivalent and free, which is why the job needs `fetch-depth: 0`.
 */
const getLastModifiedDates = () => {
  const stdout = execFileSync(
    "git",
    ["log", "--format=__C__%cI", "--name-only", "--diff-filter=AMR", "--", `${PROPOSALS_DIR}/`],
    { encoding: "utf8", maxBuffer: 256 * 1024 * 1024 }
  );

  const dates = new Map();
  let commitDate = null;
  for (const line of stdout.split("\n")) {
    if (line.startsWith("__C__")) {
      commitDate = line.slice("__C__".length).trim();
      continue;
    }
    // git log is newest first, so a path's first appearance is its latest change.
    const file = line.trim();
    if (file && commitDate && !dates.has(file)) dates.set(file, commitDate);
  }
  return dates;
};

const FRONTMATTER_RE = /^---\r?\n([\s\S]*?)\r?\n---/;

const parseFrontmatter = (contents) => {
  const match = contents.match(FRONTMATTER_RE);
  if (!match) return null;
  const attributes = {};
  for (const line of match[1].split(/\r?\n/)) {
    const attribute = line.match(/^([a-zA-Z-]+):\s*(.*)$/);
    if (attribute) attributes[attribute[1]] = attribute[2].trim();
  }
  return attributes;
};

/** Rewrites only the `status:` line inside the frontmatter block. */
const setStatusToStagnant = (contents) =>
  contents.replace(FRONTMATTER_RE, (frontmatter) =>
    frontmatter.replace(/^status:.*$/m, `status: ${STAGNANT}`)
  );

/** Every open pull request, with the files it touches and its labels. */
const fetchOpenPRs = async (github, context) => {
  const pulls = await github.paginate(github.rest.pulls.list, {
    ...context.repo,
    state: "open",
    per_page: 100
  });

  const detailed = [];
  const BATCH_SIZE = 8;
  for (let index = 0; index < pulls.length; index += BATCH_SIZE) {
    const batch = pulls.slice(index, index + BATCH_SIZE);
    const files = await Promise.all(
      batch.map((pull) =>
        github.paginate(github.rest.pulls.listFiles, {
          ...context.repo,
          pull_number: pull.number,
          per_page: 100
        })
      )
    );
    batch.forEach((pull, offset) => {
      const labels = pull.labels.map((label) => label.name);
      detailed.push({
        num: pull.number,
        createdAt: new Date(pull.created_at),
        isBot: BOT_LABELS.every((label) => labels.includes(label)),
        paths: files[offset].map((file) => file.filename)
      });
    });
  }
  return detailed;
};

/** Squash merges this bot's pull requests once the notice period has elapsed. */
const mergeElapsedPRs = async (github, context, core, botPRs) => {
  const cutoff = weeksAgo(MERGE_DELAY_WEEKS);
  const elapsed = botPRs.filter((pr) => pr.createdAt < cutoff);
  core.info(`${elapsed.length} pull requests have passed the ${MERGE_DELAY_WEEKS} week notice period`);

  for (const pr of elapsed) {
    try {
      await github.rest.pulls.merge({
        ...context.repo,
        pull_number: pr.num,
        merge_method: "squash",
        commit_title: `Move ${pr.paths[0]} to ${STAGNANT} (#${pr.num})`,
        commit_message: `Opened ${pr.createdAt.toISOString().slice(0, 10)}, more than ${MERGE_DELAY_WEEKS} weeks ago.`
      });
      core.info(`merged #${pr.num}`);
    } catch (error) {
      // Typically a conflict or a failing check; left open for a human.
      core.warning(`could not merge #${pr.num}: ${error.message}`);
    }
    await sleep(WAIT_MS);
  }
};

const openStagnantPR = async (github, context, core, candidate, baseSha) => {
  const branch = `mark-erc-${candidate.erc}-stagnant`;

  await github.rest.git.createRef({
    ...context.repo,
    ref: `refs/heads/${branch}`,
    sha: baseSha
  });

  const updated = setStatusToStagnant(candidate.contents);
  if (updated === candidate.contents)
    throw new Error(`failed to rewrite the status of ${candidate.file}`);

  await github.rest.repos.createOrUpdateFileContents({
    ...context.repo,
    path: candidate.file,
    branch,
    sha: candidate.blobSha,
    message: `Move ERC-${candidate.erc} to ${STAGNANT}`,
    content: Buffer.from(updated).toString("base64")
  });

  const { data: pull } = await github.rest.pulls.create({
    ...context.repo,
    base: DEFAULT_BRANCH,
    head: branch,
    title: `Move ERC-${candidate.erc} to ${STAGNANT}`,
    body: [
      `ERC-${candidate.erc} has not been edited since ${candidate.lastModified.slice(0, 10)},`,
      `more than ${STAGNATION_CUTOFF_MONTHS} months ago, so it is being moved from`,
      `${candidate.status} to ${STAGNANT} as described in EIP-1.\n`,
      `\nThis will be merged in ${MERGE_DELAY_WEEKS} weeks. A Stagnant proposal can be`,
      `resurrected at any time by opening a pull request moving it back to Draft.\n`,
      `\nauthors: ${candidate.author || "unknown"}\n`
    ].join(" ")
  });

  await github.rest.issues.addLabels({
    ...context.repo,
    issue_number: pull.number,
    labels: BOT_LABELS
  });

  core.info(`opened #${pull.number} for ERC-${candidate.erc}`);
};

module.exports = async ({ github, context, core, dryRun }) => {
  const openPRs = await fetchOpenPRs(github, context);
  core.info(`found ${openPRs.length} open pull requests`);

  if (!dryRun) await mergeElapsedPRs(github, context, core, openPRs.filter((pr) => pr.isBot));

  // Any file with an open pull request is left alone. This covers proposals with
  // active work in flight, and this bot's own pending pull requests, so nothing
  // is ever opened twice.
  const excluded = new Set(openPRs.flatMap((pr) => pr.paths));
  const stagnationCutoff = monthsAgo(STAGNATION_CUTOFF_MONTHS);
  const lastModifiedDates = getLastModifiedDates();

  const candidates = [];
  for (const name of fs.readdirSync(PROPOSALS_DIR)) {
    if (!name.endsWith(".md")) continue;
    const file = `${PROPOSALS_DIR}/${name}`;
    if (excluded.has(file)) continue;

    const contents = fs.readFileSync(path.join(PROPOSALS_DIR, name), "utf8");
    const frontmatter = parseFrontmatter(contents);
    if (!frontmatter || !frontmatter.status) {
      core.warning(`could not read a status from ${file}`);
      continue;
    }
    if (!STAGNATABLE_STATUSES.includes(frontmatter.status.toLowerCase())) continue;

    const lastModified = lastModifiedDates.get(file);
    if (!lastModified || new Date(lastModified) >= stagnationCutoff) continue;

    candidates.push({
      file,
      contents,
      erc: frontmatter.eip,
      status: frontmatter.status,
      author: frontmatter.author,
      lastModified
    });
  }

  // Oldest first, so the longest abandoned proposals are handled first.
  candidates.sort((a, b) => a.lastModified.localeCompare(b.lastModified));
  core.info(`${candidates.length} ERCs are eligible for ${STAGNANT}`);

  await core.summary
    .addHeading("Auto Stagnant Bot", 2)
    .addRaw(dryRun ? "Dry run: nothing was changed.\n\n" : "")
    .addTable([
      [
        { data: "ERC", header: true },
        { data: "Status", header: true },
        { data: "Last edited", header: true }
      ],
      ...candidates.map((c) => [`ERC-${c.erc}`, c.status, c.lastModified.slice(0, 10)])
    ])
    .write();

  if (dryRun || !candidates.length) return;

  const { data: base } = await github.rest.repos.getBranch({
    ...context.repo,
    branch: DEFAULT_BRANCH
  });

  for (const candidate of candidates) {
    try {
      const { data: blob } = await github.rest.repos.getContent({
        ...context.repo,
        path: candidate.file,
        ref: base.commit.sha
      });
      await openStagnantPR(
        github,
        context,
        core,
        { ...candidate, blobSha: blob.sha },
        base.commit.sha
      );
    } catch (error) {
      // One bad proposal must not stop the rest of the run.
      core.error(`failed to stagnate ERC-${candidate.erc}: ${error.message}`);
    }
    await sleep(WAIT_MS);
  }
};
