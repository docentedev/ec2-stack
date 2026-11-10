const express = require("express");
const router = express.Router({});
router.get("/health", async (_req, res, _next) => {
  res.status(200).send({ message: "OK" });
});
// export router with all routes included
module.exports = router;
