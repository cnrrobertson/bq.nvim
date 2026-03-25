return {
    buf_name = function(section) return "bq://" .. section end,
    NAMESPACE = vim.api.nvim_create_namespace("bq"),
    HL_PREFIX = "BQ",
}
