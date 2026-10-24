// @ts-check
/**
 * Moves proposals that have gone six months without an edit to Stagnant.
 *
 * Each eligible proposal gets a pull request flipping its status, which is
 * squash merged two weeks later. That delay is the author's notice period: the
 * pull request mentions them, and EIP-1 lets them resurrect it at any time.
 *
 * This replaces ethereum/EIP-Bot, which runs the same process for ethereum/EIPs
 * but looks for proposals in a hardcoded `EIPS/` directory that does not exist
 * here. It was archived in January 2023, so it cannot be fixed upstream. Nothing
 * here is ERC-specific: the directory, branch prefix and title prefix come from
 * the repository name, so this can replace EIP-Bot in ethereum/EIPs too.
 */

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const STAGNATION_CUTOFF_MONTHS = 6;
const MERGE_DELAY_WEEKS = 2;
/** Stays under GitHub's secondary rate limit; the rest are picked up on later runs. */
const MAX_NEW_PRS_PER_RUN = 50;
const STAGNATABLE_STATUSES = ["draft", "review"];
const STAGNANT = "Stagnant";

/** Identifies this bot's pull requests. Same labels the EIPs bot uses. */
const BOT_LABELS = ["created-by-bot", "1272989785"];

/** Pull requests are rate limited harder than other endpoints, so space them out. */
const RATE_LIMIT_DELAY_MS = 5000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Everything repository-specific is resolved here, so the same script can be
 * dropped into ethereum/EIPs and retire EIP-Bot in both places. The proposal
 * kind is derived from the repository name (ERCs gives ERC, EIPs gives EIP),
 * and each part can be overridden with an environment variable on the step.
 */
const resolveConfig = (context) => {
  const fromRepo = (context.repo.repo || "").replace(/s$/i, "").toUpperCase();
  const kind = (process.env.PROPOSAL_KIND || fromRepo || "ERC").toUpperCase();
  return {
    kind,
    dir: process.env.PROPOSALS_DIR || `${kind}S`,
    branchPrefix: process.env.BRANCH_PREFIX || `mark-${kind.toLowerCase()}-`,
    defaultBranch: process.env.DEFAULT_BRANCH || "master"
  };
};

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
const getLastModifiedDates = (dir) => {
  // Each commit is introduced by a NUL, so a date can never be mistaken for a
  // path. A text marker could not promise that: a file named after the marker
  // would be read as a date and attributed to every path following it.
  const stdout = execFileSync(
    "git",
    ["log", "--format=%x00%cI", "--name-only", "--diff-filter=AMR", "--", `${dir}/`],
    { encoding: "utf8", maxBuffer: 256 * 1024 * 1024 }
  );

  const dates = new Map();
  for (const commit of stdout.split("\0")) {
    const [commitDate, ...paths] = commit.split("\n");
    if (!commitDate) continue;
    for (const file of paths) {
      // git log is newest first, so a path's first appearance is its latest change.
      if (file && !dates.has(file)) dates.set(file, commitDate.trim());
    }
  }
  return dates;
};

// The s flag is what makes `.` match the newlines inside the block.
const FRONTMATTER_RE = /^---\r?\n(.*?)\r?\n---/s;

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
        branch: pull.head.ref,
        isBot: BOT_LABELS.every((label) => labels.includes(label)),
        paths: files[offset].map((file) => file.filename)
      });
    });
  }
  return detailed;
};

/** Deletes a branch this bot created. A branch left behind would block the next PR for that ERC. */
const deleteBranch = async (github, context, core, branch) => {
  try {
    await github.rest.git.deleteRef({ ...context.repo, ref: `heads/${branch}` });
  } catch (error) {
    core.warning(`could not delete branch ${branch}: ${error.message}`);
  }
};

/**
 * This does not rely on knowing what branch protection `master` carries.
 * Nothing is merged unless the pull request is clean, unopposed and passing,
 * so a red check or a reviewer's objection stops the merge either way.
 */
const isSafeToMerge = async (github, context, core, pr) => {
  const { data: pull } = await github.rest.pulls.get({ ...context.repo, pull_number: pr.num });

  if (pull.mergeable === false || ["dirty", "blocked"].includes(pull.mergeable_state)) {
    core.warning(`not merging #${pr.num}: mergeable_state is ${pull.mergeable_state}`);
    return false;
  }

  const reviews = await github.paginate(github.rest.pulls.listReviews, {
    ...context.repo,
    pull_number: pr.num,
    per_page: 100
  });
  if (reviews.some((review) => review.state === "CHANGES_REQUESTED")) {
    core.warning(`not merging #${pr.num}: a reviewer has requested changes`);
    return false;
  }

  const { data: checks } = await github.rest.checks.listForRef({
    ...context.repo,
    ref: pull.head.sha,
    per_page: 100
  });
  const failed = checks.check_runs.filter((run) =>
    ["failure", "timed_out", "cancelled", "action_required"].includes(run.conclusion)
  );
  if (failed.length) {
    core.warning(`not merging #${pr.num}: ${failed.map((run) => run.name).join(", ")} did not pass`);
    return false;
  }

  return true;
};

/**
 * Squash merges this bot's pull requests once the notice period has elapsed,
 * unless the proposal was edited after the pull request was opened. An edit
 * during the notice period means someone is working on it, so the pull request
 * is closed instead of moving a revived proposal to Stagnant.
 */
const mergeElapsedPRs = async (github, context, core, config, botPRs, lastModifiedDates) => {
  const cutoff = weeksAgo(MERGE_DELAY_WEEKS);
  const elapsed = botPRs.filter((pr) => pr.createdAt < cutoff);
  core.info(`${elapsed.length} pull requests have passed the ${MERGE_DELAY_WEEKS} week notice period`);

  for (const [index, pr] of elapsed.entries()) {
    // Paced here rather than in each branch below, so a new exit path cannot
    // skip it. Nothing to wait for before the first call.
    if (index) await sleep(RATE_LIMIT_DELAY_MS);

    const lastModified = lastModifiedDates.get(pr.paths[0]);
    if (lastModified && new Date(lastModified) > pr.createdAt) {
      try {
        await github.rest.issues.createComment({
          ...context.repo,
          issue_number: pr.num,
          body: `Closing: ${pr.paths[0]} was edited on ${lastModified.slice(0, 10)}, after this pull request was opened, so it is no longer stagnant.`
        });
        await github.rest.pulls.update({ ...context.repo, pull_number: pr.num, state: "closed" });
        await deleteBranch(github, context, core, pr.branch);
        core.info(`closed #${pr.num}: ${pr.paths[0]} was edited during the notice period`);
      } catch (error) {
        core.warning(`could not close #${pr.num}: ${error.message}`);
      }
      continue;
    }
    if (!(await isSafeToMerge(github, context, core, pr))) continue;

    try {
      await github.rest.pulls.merge({
        ...context.repo,
        pull_number: pr.num,
        merge_method: "squash",
        commit_title: `Move ${pr.paths[0]} to ${STAGNANT} (#${pr.num})`,
        commit_message: `Opened ${pr.createdAt.toISOString().slice(0, 10)}, more than ${MERGE_DELAY_WEEKS} weeks ago.`
      });
      core.info(`merged #${pr.num}`);
      await deleteBranch(github, context, core, pr.branch);
    } catch (error) {
      // Typically a conflict or a failing check; left open for a human.
      core.warning(`could not merge #${pr.num}: ${error.message}`);
    }
  }
};

const openStagnantPR = async (github, context, core, config, candidate, baseSha) => {
  const branch = `${config.branchPrefix}${candidate.erc}-stagnant`;

  const updated = setStatusToStagnant(candidate.contents);
  if (updated === candidate.contents)
    throw new Error(`failed to rewrite the status of ${candidate.file}`);

  try {
    await github.rest.git.createRef({
      ...context.repo,
      ref: `refs/heads/${branch}`,
      sha: baseSha
    });
  } catch (error) {
    // A branch left over from an earlier run: reset it to the current base.
    if (error.status !== 422) throw error;
    await github.rest.git.updateRef({
      ...context.repo,
      ref: `heads/${branch}`,
      sha: baseSha,
      force: true
    });
  }

  try {
    await createStagnantCommitAndPR(github, context, core, config, candidate, branch, updated);
  } catch (error) {
    await deleteBranch(github, context, core, branch);
    throw error;
  }
};

const createStagnantCommitAndPR = async (github, context, core, config, candidate, branch, updated) => {
  await github.rest.repos.createOrUpdateFileContents({
    ...context.repo,
    path: candidate.file,
    branch,
    sha: candidate.blobSha,
    message: `Move ${config.kind}-${candidate.erc} to ${STAGNANT}`,
    content: Buffer.from(updated).toString("base64")
  });

  const { data: pull } = await github.rest.pulls.create({
    ...context.repo,
    base: config.defaultBranch,
    head: branch,
    title: `Move ${config.kind}-${candidate.erc} to ${STAGNANT}`,
    body: [
      `${config.kind}-${candidate.erc} has not been edited since ${candidate.lastModified.slice(0, 10)},`,
      `more than ${STAGNATION_CUTOFF_MONTHS} months ago, so it is being moved from`,
      `${candidate.status} to ${STAGNANT} as described in EIP-1.\n`,
      `\nThis will be merged in ${MERGE_DELAY_WEEKS} weeks. A Stagnant proposal can be`,
      `resurrected at any time by opening a pull request moving it back to Draft.\n`,
      `\nClosing this pull request does not stop it: nothing on ${config.defaultBranch}`,
      `changes, so the next weekly run resets this branch and opens it again. To keep`,
      `${config.kind}-${candidate.erc} out of ${STAGNANT}, edit the file.\n`,
      `\nauthors: ${candidate.author || "unknown"}\n`
    ].join(" ")
  });

  await github.rest.issues.addLabels({
    ...context.repo,
    issue_number: pull.number,
    labels: BOT_LABELS
  });

  core.info(`opened #${pull.number} for ${config.kind}-${candidate.erc}`);
};

module.exports = async ({ github, context, core, dryRun }) => {
  const config = resolveConfig(context);
  core.info(`looking for stagnant ${config.kind}s in ${config.dir}/ on ${config.defaultBranch}`);

  const openPRs = await fetchOpenPRs(github, context);
  core.info(`found ${openPRs.length} open pull requests`);

  const lastModifiedDates = getLastModifiedDates(config.dir);
  if (!dryRun)
    await mergeElapsedPRs(github, context, core, config, openPRs.filter((pr) => pr.isBot), lastModifiedDates);

  // Any file with an open pull request is left alone. This covers proposals with
  // active work in flight, and this bot's own pending pull requests, so nothing
  // is ever opened twice.
  const excluded = new Set(openPRs.flatMap((pr) => pr.paths));
  const stagnationCutoff = monthsAgo(STAGNATION_CUTOFF_MONTHS);

  const candidates = [];
  for (const name of fs.readdirSync(config.dir)) {
    if (!name.endsWith(".md")) continue;
    const file = `${config.dir}/${name}`;
    if (excluded.has(file)) continue;

    const contents = fs.readFileSync(path.join(config.dir, name), "utf8");
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
  core.info(`${candidates.length} ${config.kind}s are eligible for ${STAGNANT}`);

  await core.summary
    .addHeading("Auto Stagnant Bot", 2)
    .addRaw(dryRun ? "Dry run: nothing was changed.\n\n" : "")
    .addTable([
      [
        { data: config.kind, header: true },
        { data: "Status", header: true },
        { data: "Last edited", header: true }
      ],
      ...candidates.map((c) => [`${config.kind}-${c.erc}`, c.status, c.lastModified.slice(0, 10)])
    ])
    .write();

  if (dryRun || !candidates.length) return;

  const { data: base } = await github.rest.repos.getBranch({
    ...context.repo,
    branch: config.defaultBranch
  });

  const batch = candidates.slice(0, MAX_NEW_PRS_PER_RUN);
  if (batch.length < candidates.length)
    core.info(`opening ${batch.length} this run; the remaining ${candidates.length - batch.length} follow on later runs`);

  for (const [index, candidate] of batch.entries()) {
    if (index) await sleep(RATE_LIMIT_DELAY_MS);

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
        config,
        { ...candidate, blobSha: blob.sha },
        base.commit.sha
      );
    } catch (error) {
      // One bad proposal must not stop the rest of the run.
      core.error(`failed to stagnate ${config.kind}-${candidate.erc}: ${error.message}`);
    }
  }
};
