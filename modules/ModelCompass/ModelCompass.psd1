@{
    RootModule        = 'ModelCompass.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b0a4f1e3-8c2d-4a7f-92b5-6e3d1c9a84f7'
    Author            = 'Son Nguyen'
    CompanyName       = 'ModelCompass'
    Copyright         = '(c) 2026 Son Nguyen. MIT License.'
    Description       = 'ModelCompass CLI — quản lý provider/model opencode. Lệnh: mc sync/publish/status/report/doctor/validate/connectivity/benchmark/compare/prices/spend/usage/install/restore/prune/sort-order/env/export/test/help'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('mc')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('opencode', 'ai', 'config', 'model', 'provider')
            ProjectUri = 'https://github.com/son8x/ModelCompass'
            LicenseUri = 'https://github.com/son8x/ModelCompass/blob/main/LICENSE'
        }
    }
}