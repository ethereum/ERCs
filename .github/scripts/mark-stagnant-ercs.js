// @ts-check
/**
 * Moves ERCs that have gone six months without an edit to Stagnant, opening one
 * pull request per ERC and squash merging it once its required checks pass.
 *
 * This is a port of ethereum/EIP-Bot, which drives the identical process in
 * ethereum/EIPs. That repository was archived in January 2023 and looks for
 * proposals in a hardcoded `EIPS/` directory, so it cannot be fixed upstream and
 * has never done anything here beyond failing silently.
 *
 * Behaviour follows the EIPs bot closely: same six month cutoff, same stagnatable
 * statuses, same branch names, pull request titles, bodies and labels, and the
 * same cleanup routines. Deviations are marked "DEVIATION" and explained; the
 * significant one is that pull requests are merged in the run that opens them
 * rather than two weeks later.
 */

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const PROPOSALS_DIR = "ERCS";
const PROPOSAL_PREFIX = "erc";
const STAGNATION_CUTOFF_MONTHS = 6;

/**
 * DEVIATION: the EIPs bot leaves its pull requests open for two weeks and merges
 * them during a later run's cleanup. Here they are merged in the same run, as
 * soon as the required status checks pass.
 *
 * The cleanup merge is kept as a safety net with a cutoff of zero, so anything
 * that could not be merged in its own run — checks still running when the
 * timeout expired, a transient failure — is merged by the next run instead of
 * being stranded.
 */
const MERGEABLE_CUTOFF_WEEKS = 0;
const MERGEABLE_CUTOFF_DESCRIPTION = "a previous run";

/** How long to wait for a new pull request's required checks before giving up. */
const CHECKS_TIMEOUT_MS = 30 * 60 * 1000;
const CHECKS_POLL_MS = 15 * 1000;
const STAGNATABLE_STATUSES = ["draft", "review"];
const STAGNANT = "Stagnant";

/** Pull requests are opened against this. */
const DEFAULT_BRANCH = "master";

/**
 * The marker label the EIPs bot uses to recognise its own pull requests. Kept
 * identical so tooling and saved searches behave the same across both repos.
 */
const BOT_ID = "1272989785";
const PR_KEY_LABELS = ["created-by-bot", BOT_ID];

/** EIPs excludes EIPS/eip-1.md here; this repository has no equivalent file. */
const PATHS_TO_ALWAYS_EXCLUDE = [];

/** Matches the branches this script creates, for orphan cleanup. */
const STAGNANT_BRANCH_RE = new RegExp(
  `mark-${PROPOSAL_PREFIX}-(\\d)+-stagnant-\\(\\d+-[a-zA-Z]+-.+@\\d+\\.\\d+\\.\\d+\\)`
);

/**
 * Pull requests are rate limited more aggressively than other endpoints because
 * they generate notifications, so mutating calls are spaced out.
 * https://docs.github.com/en/rest/guides/best-practices-for-integrators
 */
const WAIT_SECONDS = 5;

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const ordinal = (day) => {
  const suffixes = ["th", "st", "nd", "rd"];
  const remainder = day % 100;
  return day + (suffixes[(remainder - 20) % 10] || suffixes[remainder] || suffixes[0]);
};

/** Reproduces the EIPs bot's moment format: `(YYYY-MMM-Do@HH.m.s)`. */
const formatDate = (date) =>
  `(${date.getFullYear()}-${MONTHS[date.getMonth()]}-${ordinal(date.getDate())}` +
  `@${String(date.getHours()).padStart(2, "0")}.${date.getMinutes()}.${date.getSeconds()})`;

const wait = (seconds, core) => {
  core.info(`===== waiting ${seconds} seconds before continuing to avoid rate limiting =====`);
  return new Promise((resolve) => setTimeout(resolve, 1000 * seconds));
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
 * DEVIATION: the EIPs bot calls listCommits once per proposal to find when each
 * was last edited, which is one API request per file every run. A single
 * `git log` pass over the checkout is equivalent and costs no API quota, so this
 * job needs `fetch-depth: 0`.
 */
const getLastModifiedDates = (core) => {
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
    const file = line.trim();
    // git log is newest first, so a path's first appearance is its latest change.
    if (file && commitDate && !dates.has(file)) dates.set(file, commitDate);
  }
  core.info(`resolved last modified dates for ${dates.size} files`);
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

/**
 * Resolves the frontmatter author list to GitHub handles, matching the EIPs bot:
 * `@handle` is used as is, a bare email is looked up via user search.
 */
const getAuthorsFromFile = async (github, core, rawAuthorList, emailCache) => {
  if (!rawAuthorList) return [];

  const AUTHOR_RE = /[(<]([^>)]+)[>)]/gm;
  const authors = [...rawAuthorList.matchAll(AUTHOR_RE)].map((match) => match[1]);

  const resolved = [];
  for (const author of authors) {
    if (author.startsWith("@")) {
      resolved.push(author.toLowerCase());
      continue;
    }
    // Emails are cached because user search is limited to 30 requests a minute.
    if (emailCache.has(author)) {
      resolved.push(emailCache.get(author));
      continue;
    }
    let value = author.toLowerCase();
    try {
      const { data } = await github.rest.search.users({ q: author });
      if (data.total_count > 0 && data.items[0]) value = "@" + data.items[0].login;
      else core.warning(`no github user found, using email instead: ${author}`);
    } catch (error) {
      core.warning(`failed to resolve author ${author}: ${error.message}`);
    }
    emailCache.set(author, value);
    resolved.push(value);
  }

  return [...new Set(resolved)];
};

/**
 * Every open pull request, with its files and labels.
 *
 * DEVIATION: the EIPs bot uses the search API for this and its pagination is
 * broken, because fetchNonBotPRs recurses into fetchBotCreatedPRs for page two
 * onwards and silently returns bot pull requests instead of the rest of the
 * non-bot ones. This repository currently has more than 100 open pull requests,
 * so that bug would matter here. Listing pull requests directly is exact,
 * paginates correctly and avoids the search API's tighter rate limit.
 */
const fetchOpenPRs = async (github, context, core) => {
  const pulls = await github.paginate(github.rest.pulls.list, {
    ...context.repo,
    state: "open",
    per_page: 100
  });
  core.info(`found ${pulls.length} open pull requests`);

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
        author: pull.user && pull.user.login,
        branch: pull.head.ref,
        createdAt: new Date(pull.created_at),
        labels,
        isBot: PR_KEY_LABELS.every((label) => labels.includes(label)),
        paths: files[offset].map((file) => file.filename)
      });
    });
  }
  return detailed;
};

const closePRByNum = async (github, context, core, prNum, branch) => {
  await github.rest.pulls.update({ ...context.repo, pull_number: prNum, state: "closed" });
  core.info(`successfully closed PR ${prNum}`);
  await deleteBranch(github, context, core, branch);
};

const deleteBranch = async (github, context, core, branch) => {
  if (!branch) return;
  try {
    await github.rest.git.deleteRef({ ...context.repo, ref: `heads/${branch}` });
    core.info(`successfully deleted branch ${branch}`);
  } catch (error) {
    core.warning(`failed to delete branch ${branch}: ${error.message}`);
  }
};

/**
 * Closes bot labelled pull requests that this account did not open, unless
 * somebody has commented on them.
 */
const closeNonSelfBotPRs = async (github, context, core, botPRs) => {
  const { data: me } = await github.rest.users.getAuthenticated();
  const nonSelf = botPRs.filter((pr) => pr.author !== me.login);

  for (const pr of nonSelf) {
    const comments = await github.paginate(github.rest.issues.listComments, {
      ...context.repo,
      issue_number: pr.num,
      per_page: 100
    });
    if (comments.some((comment) => comment.user && comment.user.login !== me.login)) {
      core.info(`PR ${pr.num} will not be closed because a comment was left on it`);
      continue;
    }
    core.info(
      `closing PR ${pr.num} because its author is ${pr.author} but this script runs as ${me.login}`
    );
    await closePRByNum(github, context, core, pr.num, pr.branch);
    await wait(WAIT_SECONDS, core);
  }
};

/** Where the bot has more than one open PR for a path, keeps the first. */
const closeRepeatPRs = async (github, context, core, botPRs) => {
  const byPath = new Map();
  for (const pr of botPRs) {
    const path = pr.paths[0];
    if (!path) continue;
    if (!byPath.has(path)) byPath.set(path, []);
    byPath.get(path).push(pr);
  }

  for (const [path, prs] of byPath) {
    if (prs.length < 2) continue;
    core.warning(`bot has ${prs.length} PRs open for ${path}`);
    for (const pr of prs.slice(1)) {
      await closePRByNum(github, context, core, pr.num, pr.branch);
      await wait(WAIT_SECONDS, core);
    }
  }
};

const squashMerge = async (github, context, core, prNum, filePath, message) => {
  try {
    await github.rest.pulls.merge({
      ...context.repo,
      pull_number: prNum,
      merge_method: "squash",
      commit_title: `(bot ${BOT_ID}) moving ${filePath} to stagnant (#${prNum})`,
      commit_message: message
    });
    core.info("succesfully merged");
    return true;
  } catch (error) {
    core.warning(`failed to merge ${prNum}: ${error.message}`);
    return false;
  }
};

/**
 * Blocks until a pull request's required status checks have settled.
 *
 * `mergeable_state` is `blocked` while required checks are pending or failing,
 * `clean` once they pass, and `unstable` when only non-required checks are
 * failing, which protection still allows to merge. Returns false on timeout or
 * conflict, leaving the pull request open for the next run's cleanup to merge.
 */
const waitForMergeable = async (github, context, core, prNum) => {
  const deadline = Date.now() + CHECKS_TIMEOUT_MS;

  while (Date.now() < deadline) {
    const { data: pr } = await github.rest.pulls.get({
      ...context.repo,
      pull_number: prNum
    });

    if (pr.merged) return false;
    if (pr.mergeable_state === "clean" || pr.mergeable_state === "unstable") return true;
    if (pr.mergeable_state === "dirty") {
      core.warning(`PR ${prNum} has conflicts and will be left for manual review`);
      return false;
    }
    await new Promise((resolve) => setTimeout(resolve, CHECKS_POLL_MS));
  }

  core.warning(
    `PR ${prNum} checks did not settle within ${CHECKS_TIMEOUT_MS / 60000} minutes; ` +
      `leaving it open for the next run to merge`
  );
  return false;
};

/**
 * Safety net: squash merges bot pull requests left over from earlier runs, so a
 * pull request whose checks were still running at timeout is not stranded.
 */
const mergeOldPRs = async (github, context, core, botPRs) => {
  const cutoff = weeksAgo(MERGEABLE_CUTOFF_WEEKS);
  const mergeable = botPRs.filter((pr) => pr.createdAt < cutoff);

  for (const pr of mergeable) {
    const message = [
      `PR ${pr.num} with changes to ${pr.paths[0]} was created on`,
      `\n\t${formatDate(pr.createdAt)}`,
      `which is before the cutoff date of \n\t${formatDate(cutoff)}`,
      `i.e. ${MERGEABLE_CUTOFF_DESCRIPTION}`
    ].join(" ");
    core.info(message);
    if (await waitForMergeable(github, context, core, pr.num))
      await squashMerge(github, context, core, pr.num, pr.paths[0], message);
    await wait(WAIT_SECONDS, core);
  }
};

/** Deletes leftover bot branches that no longer have a pull request. */
const deleteOrphanedBranches = async (github, context, core, botPRs) => {
  const refs = await github.paginate(github.rest.git.listMatchingRefs, {
    ...context.repo,
    ref: "heads",
    per_page: 100
  });
  core.info(`successfully found ${refs.length} references`);

  const active = new Set(botPRs.map((pr) => pr.branch));
  const orphaned = refs
    .map((ref) => {
      const match = ref.ref.match(STAGNANT_BRANCH_RE);
      return match ? match[0] : null;
    })
    .filter((branch) => branch && !active.has(branch));

  core.info(`extracted ${orphaned.length} orphaned bot created branches`);
  for (const branch of orphaned) {
    await deleteBranch(github, context, core, branch);
    await wait(WAIT_SECONDS, core);
  }
};

/** Creates the branch, commit, pull request and labels for a single ERC. */
const applyStagnantProtocol = async (github, context, core, candidate, baseSha, emailCache) => {
  core.info(`\n================ ERC ${candidate.erc}`);

  const now = formatDate(new Date());
  const branch = `mark-${PROPOSAL_PREFIX}-${candidate.erc}-stagnant-${now}`;

  await github.rest.git.createRef({ ...context.repo, ref: `refs/heads/${branch}`, sha: baseSha });
  core.info(`successfully created branch ${branch}`);
  await new Promise((resolve) => setTimeout(resolve, 1000));

  const updated = setStatusToStagnant(candidate.contents);
  if (updated === candidate.contents)
    throw new Error(`failed to rewrite the status of ${candidate.file}`);

  await github.rest.repos.createOrUpdateFileContents({
    ...context.repo,
    path: candidate.file,
    branch,
    sha: candidate.blobSha,
    message: `Updating ${candidate.file} to status ${STAGNANT.toLowerCase()}`,
    content: Buffer.from(updated).toString("base64")
  });
  core.info(`Updating ${candidate.file} to status ${STAGNANT.toLowerCase()}`);

  const authors = await getAuthorsFromFile(github, core, candidate.author, emailCache);
  await new Promise((resolve) => setTimeout(resolve, 1000));

  const { data: pull } = await github.rest.pulls.create({
    ...context.repo,
    base: DEFAULT_BRANCH,
    head: branch,
    title: `ERC-${candidate.erc} stagnant ${now}`,
    body: [
      `This ERC has not been active since ${formatDate(new Date(candidate.lastModified))};`,
      `which, is greater than the allowed time of ${STAGNATION_CUTOFF_MONTHS} months.\n\n`,
      `authors: ${authors.join(", ")} \n`
    ].join(" "),
    draft: true
  });
  core.info(`successfully created draft pull request titled ${pull.title}`);

  await github.rest.issues.addLabels({
    ...context.repo,
    issue_number: pull.number,
    labels: PR_KEY_LABELS
  });

  // Opening as a draft and then marking it ready lets the merge bot skip it.
  await github.graphql(
    `mutation($id: ID!) { markPullRequestReadyForReview(input: {pullRequestId: $id}) { clientMutationId } }`,
    { id: pull.node_id }
  );
  core.info(`successfully marked PR ${pull.number} as ready for review`);

  await wait(WAIT_SECONDS, core);
  return pull.number;
};

module.exports = async ({ github, context, core, dryRun }) => {
  const stagnationCutoff = monthsAgo(STAGNATION_CUTOFF_MONTHS);
  const openPRs = await fetchOpenPRs(github, context, core);
  const botPRs = openPRs.filter((pr) => pr.isBot);
  const emailCache = new Map();

  // ---- cleanup, mirroring the EIPs bot's botCleanup() ----
  if (!dryRun) {
    await closeNonSelfBotPRs(github, context, core, botPRs);
    await closeRepeatPRs(github, context, core, botPRs);
    await mergeOldPRs(github, context, core, botPRs);
    await deleteOrphanedBranches(github, context, core, botPRs);
    core.info("\n\t====== CLEANUP COMPLETE =====\n");
  }

  // ---- selection ----
  core.info(
    `checking for stagnant ERCs that weren't edited before ${stagnationCutoff.toISOString()}`
  );
  const lastModifiedDates = getLastModifiedDates(core);

  const pathsToExclude = new Set([
    ...PATHS_TO_ALWAYS_EXCLUDE,
    // Anything an open pull request already touches, bot or otherwise.
    ...openPRs.flatMap((pr) => pr.paths)
  ]);

  const candidates = [];
  for (const name of fs.readdirSync(PROPOSALS_DIR)) {
    if (!name.endsWith(".md")) continue;
    const file = `${PROPOSALS_DIR}/${name}`;

    const contents = fs.readFileSync(path.join(PROPOSALS_DIR, name), "utf8");
    const frontmatter = parseFrontmatter(contents);
    if (!frontmatter || !frontmatter.status) {
      core.warning(`failed to collect 'status' from ${file}`);
      continue;
    }
    if (!STAGNATABLE_STATUSES.includes(frontmatter.status.toLowerCase())) continue;

    const lastModified = lastModifiedDates.get(file);
    if (!lastModified) {
      core.warning(`${file} did not resolve to a commit`);
      continue;
    }
    if (new Date(lastModified) >= stagnationCutoff) continue;
    if (pathsToExclude.has(file)) {
      core.info(`skipping ${file}: an open pull request already touches it`);
      continue;
    }

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

  await core.summary
    .addHeading("Auto Stagnant Bot", 2)
    .addRaw(
      dryRun
        ? "Dry run: no branches, pull requests or merges were created.\n\n"
        : `Opening and merging ${candidates.length} pull requests.\n\n`
    )
    .addTable([
      [
        { data: "ERC", header: true },
        { data: "Status", header: true },
        { data: "Last edited", header: true }
      ],
      ...candidates.map((candidate) => [
        `ERC-${candidate.erc}`,
        candidate.status,
        candidate.lastModified.slice(0, 10)
      ])
    ])
    .write();

  if (!candidates.length) {
    core.info(`No ERCs were found to be last edited before ${stagnationCutoff.toISOString()}`);
    return;
  }
  core.info(`${candidates.length} ERCs will be moved to ${STAGNANT}`);

  if (dryRun) {
    core.info("dry run: stopping before making any changes");
    return;
  }

  const { data: base } = await github.rest.repos.getBranch({
    ...context.repo,
    branch: DEFAULT_BRANCH
  });

  // ---- phase one: open every pull request ----
  //
  // Opening and merging are separated deliberately. Merging each pull request
  // straight after opening it would idle the job for the several minutes its
  // required checks take, and 200+ proposals of that would exceed the six hour
  // job limit. Opening them all first means the checks for the earliest ones
  // have long since finished by the time the merge pass reaches them.
  //
  // Runs serially to avoid race conditions and rate limiters.
  const opened = [];
  for (const candidate of candidates) {
    try {
      const { data: blob } = await github.rest.repos.getContent({
        ...context.repo,
        path: candidate.file,
        ref: base.commit.sha
      });
      const num = await applyStagnantProtocol(
        github,
        context,
        core,
        { ...candidate, blobSha: blob.sha },
        base.commit.sha,
        emailCache
      );
      opened.push({ num, file: candidate.file, erc: candidate.erc });
    } catch (error) {
      // One bad proposal must not stop the rest of the run.
      core.error(`failed to stagnate ERC-${candidate.erc}: ${error.message}`);
    }
  }

  // ---- phase two: merge them as their checks pass ----
  core.info(`\n\t====== MERGING ${opened.length} PULL REQUESTS =====\n`);
  let merged = 0;
  for (const pr of opened) {
    core.info(`\n================ ERC ${pr.erc} (#${pr.num})`);
    if (!(await waitForMergeable(github, context, core, pr.num))) continue;

    const message = [
      `Moving ${pr.file} to ${STAGNANT.toLowerCase()}, as it had not been edited`,
      `in over ${STAGNATION_CUTOFF_MONTHS} months.`
    ].join(" ");
    if (await squashMerge(github, context, core, pr.num, pr.file, message)) merged++;
    await wait(WAIT_SECONDS, core);
  }

  core.info(`merged ${merged} of ${opened.length} pull requests`);
  if (merged < opened.length)
    core.info(
      `${opened.length - merged} remain open and will be merged by the next run's cleanup`
    );
};
