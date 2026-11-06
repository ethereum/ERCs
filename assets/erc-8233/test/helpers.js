module.exports = {
  assertDeploymentRejectedWithCustomError: async function (
    customError,
    deploymentPromise,
  ) {
    const error = await expect(deploymentPromise).to.be.rejected

    expect(error)
      .to.have.property("message")
      .that.contains(
        customError,
        `Expected error ${expectedError}, but got ${error.message}`,
      )
  },
}
