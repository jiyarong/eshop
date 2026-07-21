# frozen_string_literal: true

require "bigdecimal"

# 用法:
#   bundle exec rails runner script/import_sku_dimensions_from_npd_xlsx.rb
#   APPLY=1 bundle exec rails runner script/import_sku_dimensions_from_npd_xlsx.rb
#   SKU_CODES=SKU1,SKU2 bundle exec rails runner script/import_sku_dimensions_from_npd_xlsx.rb
#
# 这是从 /Users/jiyarong/Downloads/npd.xlsx 抽取后的自包含导入脚本，不再依赖 XLSX 文件。
# 字段映射:
#   SKU                       -> ec_sku_dimensions.sku_code
#   Inner Wt (kg)             -> ec_sku_dimensions.inner_box_weight_kg
#   Master CTN Size (cm)      -> ec_sku_dimensions.outer_length_cm / outer_width_cm / outer_height_cm
#   Master GW (kg)            -> ec_sku_dimensions.outer_box_weight_kg
#   PCS/CTN                   -> ec_sku_dimensions.outer_box_pcs

class NpdSkuDimensionsImport
  IMPORT_ROWS = [
    { source_row: 4, sku_code: "JJ006-BK", inner_box_weight_kg: BigDecimal("2.5"), outer_length_cm: BigDecimal("68"), outer_width_cm: BigDecimal("38"), outer_height_cm: BigDecimal("7"), outer_box_weight_kg: BigDecimal("2.85"), outer_box_pcs: 1 },
    { source_row: 5, sku_code: "JJ006-WT", inner_box_weight_kg: BigDecimal("2.5"), outer_length_cm: BigDecimal("68"), outer_width_cm: BigDecimal("38"), outer_height_cm: BigDecimal("7"), outer_box_weight_kg: BigDecimal("2.85"), outer_box_pcs: 1 },
    { source_row: 6, sku_code: "JJ008-WC", inner_box_weight_kg: BigDecimal("13"), outer_length_cm: BigDecimal("64"), outer_width_cm: BigDecimal("39"), outer_height_cm: BigDecimal("14"), outer_box_weight_kg: BigDecimal("14"), outer_box_pcs: 1 },
    { source_row: 7, sku_code: "JJ008-BK", inner_box_weight_kg: BigDecimal("13"), outer_length_cm: BigDecimal("64"), outer_width_cm: BigDecimal("39"), outer_height_cm: BigDecimal("14"), outer_box_weight_kg: BigDecimal("14"), outer_box_pcs: 1 },
    { source_row: 8, sku_code: "JJ007-BK", inner_box_weight_kg: BigDecimal("4.5"), outer_length_cm: BigDecimal("64"), outer_width_cm: BigDecimal("34"), outer_height_cm: BigDecimal("8"), outer_box_weight_kg: BigDecimal("5"), outer_box_pcs: 1 },
    { source_row: 9, sku_code: "JJ007-WC", inner_box_weight_kg: BigDecimal("4.5"), outer_length_cm: BigDecimal("64"), outer_width_cm: BigDecimal("34"), outer_height_cm: BigDecimal("8"), outer_box_weight_kg: BigDecimal("5"), outer_box_pcs: 1 },
    { source_row: 10, sku_code: "BB001-BK" },
    { source_row: 11, sku_code: "BB001-BN" },
    { source_row: 12, sku_code: "BB001-CF" },
    { source_row: 13, sku_code: "BB002-BK" },
    { source_row: 14, sku_code: "BB002-EY" },
    { source_row: 15, sku_code: "BB002-CF" },
    { source_row: 16, sku_code: "BB003-BK" },
    { source_row: 17, sku_code: "BB003-CF" },
    { source_row: 18, sku_code: "BB004-BN" },
    { source_row: 19, sku_code: "BB005-BK" },
    { source_row: 20, sku_code: "BB005-BE" },
    { source_row: 21, sku_code: "BB006-BK" },
    { source_row: 22, sku_code: "BB006-CF" },
    { source_row: 23, sku_code: "BB007-BK" },
    { source_row: 24, sku_code: "BB007-CF" },
    { source_row: 25, sku_code: "BB008-BK" },
    { source_row: 26, sku_code: "BB008-CF" },
    { source_row: 27, sku_code: "BB009-BK" },
    { source_row: 28, sku_code: "BB009-CF" },
    { source_row: 29, sku_code: "BB010-BK" },
    { source_row: 30, sku_code: "BB010-CF" },
    { source_row: 31, sku_code: "BB011-BK" },
    { source_row: 32, sku_code: "BB011-CF" },
    { source_row: 33, sku_code: "BB012", inner_box_weight_kg: BigDecimal("0.35"), outer_length_cm: BigDecimal("63"), outer_width_cm: BigDecimal("47"), outer_height_cm: BigDecimal("50"), outer_box_weight_kg: BigDecimal("36"), outer_box_pcs: 100 },
    { source_row: 34, sku_code: "CYQ85-WT", inner_box_weight_kg: BigDecimal("0.3"), outer_length_cm: BigDecimal("48"), outer_width_cm: BigDecimal("39"), outer_height_cm: BigDecimal("40"), outer_box_weight_kg: BigDecimal("18"), outer_box_pcs: 60 },
    { source_row: 35, sku_code: "CYQ85-BK", inner_box_weight_kg: BigDecimal("0.3"), outer_length_cm: BigDecimal("48"), outer_width_cm: BigDecimal("39"), outer_height_cm: BigDecimal("40"), outer_box_weight_kg: BigDecimal("18"), outer_box_pcs: 60 },
    { source_row: 36, sku_code: "CYQ86-WT", inner_box_weight_kg: BigDecimal("0.43"), outer_length_cm: BigDecimal("47.5"), outer_width_cm: BigDecimal("40"), outer_height_cm: BigDecimal("53"), outer_box_weight_kg: BigDecimal("18.2"), outer_box_pcs: 40 },
    { source_row: 37, sku_code: "CYQ86-BK", inner_box_weight_kg: BigDecimal("0.43"), outer_length_cm: BigDecimal("47.5"), outer_width_cm: BigDecimal("40"), outer_height_cm: BigDecimal("53"), outer_box_weight_kg: BigDecimal("18.2"), outer_box_pcs: 40 },
    { source_row: 38, sku_code: "QJD002-33", inner_box_weight_kg: BigDecimal("12"), outer_length_cm: BigDecimal("89"), outer_width_cm: BigDecimal("26.5"), outer_height_cm: BigDecimal("14"), outer_box_weight_kg: BigDecimal("13"), outer_box_pcs: 1 },
    { source_row: 39, sku_code: "QJD002-48", inner_box_weight_kg: BigDecimal("13"), outer_length_cm: BigDecimal("126"), outer_width_cm: BigDecimal("26.5"), outer_height_cm: BigDecimal("14"), outer_box_weight_kg: BigDecimal("14"), outer_box_pcs: 1 },
    { source_row: 40, sku_code: "QJD002-60", inner_box_weight_kg: BigDecimal("14"), outer_length_cm: BigDecimal("157"), outer_width_cm: BigDecimal("26.5"), outer_height_cm: BigDecimal("14"), outer_box_weight_kg: BigDecimal("15"), outer_box_pcs: 1 },
    { source_row: 41, sku_code: "QJD001-3", inner_box_weight_kg: BigDecimal("15.25"), outer_length_cm: BigDecimal("43"), outer_width_cm: BigDecimal("37"), outer_height_cm: BigDecimal("17"), outer_box_weight_kg: BigDecimal("15.9"), outer_box_pcs: 1 },
    { source_row: 42, sku_code: "QJD001-5", inner_box_weight_kg: BigDecimal("22"), outer_length_cm: BigDecimal("48"), outer_width_cm: BigDecimal("50"), outer_height_cm: BigDecimal("20"), outer_box_weight_kg: BigDecimal("23"), outer_box_pcs: 1 },
    { source_row: 43, sku_code: "QJD003-RD", inner_box_weight_kg: BigDecimal("4.5"), outer_length_cm: BigDecimal("43.5"), outer_width_cm: BigDecimal("40.5"), outer_height_cm: BigDecimal("36"), outer_box_weight_kg: BigDecimal("5"), outer_box_pcs: 4 },
    { source_row: 44, sku_code: "QJD003-BK", inner_box_weight_kg: BigDecimal("4.5"), outer_length_cm: BigDecimal("43.5"), outer_width_cm: BigDecimal("40.5"), outer_height_cm: BigDecimal("36"), outer_box_weight_kg: BigDecimal("5"), outer_box_pcs: 4 },
    { source_row: 45, sku_code: "QJD003-YL", inner_box_weight_kg: BigDecimal("4.5"), outer_length_cm: BigDecimal("43.5"), outer_width_cm: BigDecimal("40.5"), outer_height_cm: BigDecimal("36"), outer_box_weight_kg: BigDecimal("5"), outer_box_pcs: 4 },
    { source_row: 46, sku_code: "QJD004-2", outer_length_cm: BigDecimal("44.5"), outer_width_cm: BigDecimal("39.5"), outer_height_cm: BigDecimal("29.5"), outer_box_weight_kg: BigDecimal("1.7"), outer_box_pcs: 9 },
    { source_row: 47, sku_code: "QJD004-3", outer_length_cm: BigDecimal("49"), outer_width_cm: BigDecimal("49"), outer_height_cm: BigDecimal("27"), outer_box_weight_kg: BigDecimal("2.5"), outer_box_pcs: 10 },
    { source_row: 48, sku_code: "KJ-201-BK", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 49, sku_code: "KJ-201-GY", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 50, sku_code: "KJ-201-SV", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 51, sku_code: "KJ-201-GD", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 52, sku_code: "KJ-205-BK", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("66"), outer_height_cm: BigDecimal("30") },
    { source_row: 53, sku_code: "KJ-205-GY", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("66"), outer_height_cm: BigDecimal("30") },
    { source_row: 54, sku_code: "KJ-205-SV", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("66"), outer_height_cm: BigDecimal("30") },
    { source_row: 55, sku_code: "KJ-205-GD", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("66"), outer_height_cm: BigDecimal("30") },
    { source_row: 56, sku_code: "KJ-206-BK", outer_length_cm: BigDecimal("44"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 57, sku_code: "KJ-206-GY", outer_length_cm: BigDecimal("44"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 58, sku_code: "KJ-206-SV", outer_length_cm: BigDecimal("44"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 59, sku_code: "KJ-206-GD", outer_length_cm: BigDecimal("44"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 60, sku_code: "KJ-208-BK", outer_length_cm: BigDecimal("37"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 61, sku_code: "KJ-208-GY", outer_length_cm: BigDecimal("37"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 62, sku_code: "KJ-208-SV", outer_length_cm: BigDecimal("37"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 63, sku_code: "KJ-208-GD", outer_length_cm: BigDecimal("37"), outer_width_cm: BigDecimal("76"), outer_height_cm: BigDecimal("30") },
    { source_row: 64, sku_code: "JJ004-4", outer_length_cm: BigDecimal("92"), outer_width_cm: BigDecimal("31"), outer_height_cm: BigDecimal("6"), outer_box_weight_kg: BigDecimal("6.9"), outer_box_pcs: 1 },
    { source_row: 65, sku_code: "JJ004-5", outer_length_cm: BigDecimal("93"), outer_width_cm: BigDecimal("31"), outer_height_cm: BigDecimal("7"), outer_box_weight_kg: BigDecimal("8.2"), outer_box_pcs: 1 },
    { source_row: 66, sku_code: "JJ004-6", outer_length_cm: BigDecimal("93"), outer_width_cm: BigDecimal("41"), outer_height_cm: BigDecimal("7"), outer_box_weight_kg: BigDecimal("13"), outer_box_pcs: 1 },
    { source_row: 67, sku_code: "JJ005-4", outer_length_cm: BigDecimal("92"), outer_width_cm: BigDecimal("31"), outer_height_cm: BigDecimal("6"), outer_box_weight_kg: BigDecimal("6.5"), outer_box_pcs: 1 },
    { source_row: 68, sku_code: "JJ005-5", outer_length_cm: BigDecimal("93"), outer_width_cm: BigDecimal("31"), outer_height_cm: BigDecimal("7"), outer_box_weight_kg: BigDecimal("7.7"), outer_box_pcs: 1 },
    { source_row: 69, sku_code: "JJ005-6", outer_length_cm: BigDecimal("93"), outer_width_cm: BigDecimal("41"), outer_height_cm: BigDecimal("7"), outer_box_weight_kg: BigDecimal("11.1"), outer_box_pcs: 1 },
    { source_row: 71, sku_code: "ZP001-OR", outer_length_cm: BigDecimal("170"), outer_width_cm: BigDecimal("27"), outer_height_cm: BigDecimal("27"), outer_box_pcs: 1 },
    { source_row: 72, sku_code: "ZP001-BL", outer_length_cm: BigDecimal("170"), outer_width_cm: BigDecimal("27"), outer_height_cm: BigDecimal("27"), outer_box_pcs: 1 },
    { source_row: 73, sku_code: "KSD001", outer_length_cm: BigDecimal("63"), outer_width_cm: BigDecimal("15"), outer_height_cm: BigDecimal("63"), outer_box_weight_kg: BigDecimal("3.6"), outer_box_pcs: 1 },
    { source_row: 74, sku_code: "KSD002", outer_length_cm: BigDecimal("63"), outer_width_cm: BigDecimal("13"), outer_height_cm: BigDecimal("63"), outer_box_weight_kg: BigDecimal("3.6"), outer_box_pcs: 1 },
    { source_row: 75, sku_code: "KSD003", outer_length_cm: BigDecimal("63"), outer_width_cm: BigDecimal("15"), outer_height_cm: BigDecimal("63"), outer_box_weight_kg: BigDecimal("4.5"), outer_box_pcs: 1 },
    { source_row: 76, sku_code: "KSD004", outer_length_cm: BigDecimal("63"), outer_width_cm: BigDecimal("15"), outer_height_cm: BigDecimal("63"), outer_box_weight_kg: BigDecimal("3.6"), outer_box_pcs: 1 },
    { source_row: 77, sku_code: "KSD005-S", outer_length_cm: BigDecimal("98"), outer_width_cm: BigDecimal("29"), outer_height_cm: BigDecimal("32"), outer_box_weight_kg: BigDecimal("7"), outer_box_pcs: 1 },
    { source_row: 78, sku_code: "KSD005-L", outer_length_cm: BigDecimal("118"), outer_width_cm: BigDecimal("33"), outer_height_cm: BigDecimal("32"), outer_box_weight_kg: BigDecimal("10"), outer_box_pcs: 1 },
    { source_row: 79, sku_code: "LSD001-S", outer_length_cm: BigDecimal("62"), outer_width_cm: BigDecimal("14"), outer_height_cm: BigDecimal("62"), outer_box_weight_kg: BigDecimal("3"), outer_box_pcs: 1 },
    { source_row: 80, sku_code: "LSD001-M", outer_length_cm: BigDecimal("72"), outer_width_cm: BigDecimal("14"), outer_height_cm: BigDecimal("72"), outer_box_weight_kg: BigDecimal("4"), outer_box_pcs: 1 },
    { source_row: 81, sku_code: "LSD001-L", outer_length_cm: BigDecimal("82"), outer_width_cm: BigDecimal("14"), outer_height_cm: BigDecimal("82"), outer_box_weight_kg: BigDecimal("5"), outer_box_pcs: 1 },
    { source_row: 82, sku_code: "CYQ91-PP", inner_box_weight_kg: BigDecimal("0.4"), outer_length_cm: BigDecimal("33"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("43"), outer_box_weight_kg: BigDecimal("16.5"), outer_box_pcs: 40 },
    { source_row: 83, sku_code: "CYQ91-PK", inner_box_weight_kg: BigDecimal("0.4"), outer_length_cm: BigDecimal("33"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("43"), outer_box_weight_kg: BigDecimal("16.5"), outer_box_pcs: 40 },
    { source_row: 84, sku_code: "CYQ91-BL", inner_box_weight_kg: BigDecimal("0.4"), outer_length_cm: BigDecimal("33"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("43"), outer_box_weight_kg: BigDecimal("16.5"), outer_box_pcs: 40 },
    { source_row: 85, sku_code: "CYQ91-GN", inner_box_weight_kg: BigDecimal("0.4"), outer_length_cm: BigDecimal("33"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("43"), outer_box_weight_kg: BigDecimal("16.5"), outer_box_pcs: 40 },
    { source_row: 86, sku_code: "KJ-203-GD", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("38"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 87, sku_code: "KJ-203-GY", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("38"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 88, sku_code: "KJ-203-RS", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("38"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 89, sku_code: "KJ-223-GD", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("38"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 90, sku_code: "KJ-223-GY", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("38"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 91, sku_code: "KJ-223-RS", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("38"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 92, sku_code: "CZ001-BK", inner_box_weight_kg: BigDecimal("1.03"), outer_length_cm: BigDecimal("37"), outer_width_cm: BigDecimal("60"), outer_height_cm: BigDecimal("55"), outer_box_weight_kg: BigDecimal("16.3"), outer_box_pcs: 15 },
    { source_row: 93, sku_code: "CZ001-SV", inner_box_weight_kg: BigDecimal("1.03"), outer_length_cm: BigDecimal("37"), outer_width_cm: BigDecimal("60"), outer_height_cm: BigDecimal("55"), outer_box_weight_kg: BigDecimal("16.3"), outer_box_pcs: 15 },
    { source_row: 94, sku_code: "CZ001-GD", inner_box_weight_kg: BigDecimal("1.03"), outer_length_cm: BigDecimal("37"), outer_width_cm: BigDecimal("60"), outer_height_cm: BigDecimal("55"), outer_box_weight_kg: BigDecimal("16.3"), outer_box_pcs: 15 },
    { source_row: 95, sku_code: "HJ001-BK", inner_box_weight_kg: BigDecimal("4.5"), outer_length_cm: BigDecimal("73"), outer_width_cm: BigDecimal("43"), outer_height_cm: BigDecimal("4.5"), outer_box_weight_kg: BigDecimal("4.8"), outer_box_pcs: 1 },
    { source_row: 96, sku_code: "HJ001-GD", inner_box_weight_kg: BigDecimal("4.5"), outer_length_cm: BigDecimal("73"), outer_width_cm: BigDecimal("43"), outer_height_cm: BigDecimal("4.5"), outer_box_weight_kg: BigDecimal("4.9"), outer_box_pcs: 1 },
    { source_row: 97, sku_code: "HJ002-BK", inner_box_weight_kg: BigDecimal("4.1"), outer_length_cm: BigDecimal("73"), outer_width_cm: BigDecimal("43"), outer_height_cm: BigDecimal("4.5"), outer_box_weight_kg: BigDecimal("4.5"), outer_box_pcs: 1 },
    { source_row: 98, sku_code: "HJ004", outer_length_cm: BigDecimal("78"), outer_width_cm: BigDecimal("32"), outer_height_cm: BigDecimal("5"), outer_box_weight_kg: BigDecimal("3"), outer_box_pcs: 1 },
    { source_row: 99, sku_code: "HJ005", outer_length_cm: BigDecimal("88"), outer_width_cm: BigDecimal("32"), outer_height_cm: BigDecimal("6.5"), outer_box_weight_kg: BigDecimal("5"), outer_box_pcs: 1 },
    { source_row: 100, sku_code: "HJ006", outer_length_cm: BigDecimal("73"), outer_width_cm: BigDecimal("32"), outer_height_cm: BigDecimal("7"), outer_box_weight_kg: BigDecimal("5"), outer_box_pcs: 1 },
    { source_row: 101, sku_code: "HJ007", outer_length_cm: BigDecimal("85"), outer_width_cm: BigDecimal("32"), outer_height_cm: BigDecimal("6.5"), outer_box_weight_kg: BigDecimal("5"), outer_box_pcs: 1 },
    { source_row: 102, sku_code: "KJ-202-GD", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 103, sku_code: "KJ-202-SV", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 104, sku_code: "KJ-202-BK", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 105, sku_code: "KJ-222-GD", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 106, sku_code: "KJ-222-SV", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 107, sku_code: "KJ-222-BK", outer_length_cm: BigDecimal("81"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("22"), outer_box_pcs: 4 },
    { source_row: 108, sku_code: "SLHL001-1", outer_length_cm: BigDecimal("27"), outer_width_cm: BigDecimal("20"), outer_height_cm: BigDecimal("16"), outer_box_weight_kg: BigDecimal("8"), outer_box_pcs: 1 },
    { source_row: 109, sku_code: "SLHL001-2", outer_length_cm: BigDecimal("30"), outer_width_cm: BigDecimal("20"), outer_height_cm: BigDecimal("16"), outer_box_weight_kg: BigDecimal("11.5"), outer_box_pcs: 1 },
    { source_row: 110, sku_code: "SLHL002-1", outer_length_cm: BigDecimal("27"), outer_width_cm: BigDecimal("20"), outer_height_cm: BigDecimal("16"), outer_box_weight_kg: BigDecimal("8.2"), outer_box_pcs: 1 },
    { source_row: 111, sku_code: "SLHL002-2", outer_length_cm: BigDecimal("30"), outer_width_cm: BigDecimal("20"), outer_height_cm: BigDecimal("16"), outer_box_weight_kg: BigDecimal("11.7"), outer_box_pcs: 1 },
    { source_row: 112, sku_code: "ZJ090", inner_box_weight_kg: BigDecimal("6.6"), outer_length_cm: BigDecimal("66"), outer_width_cm: BigDecimal("27"), outer_height_cm: BigDecimal("9.5"), outer_box_weight_kg: BigDecimal("6.6"), outer_box_pcs: 1 },
    { source_row: 113, sku_code: "ZJ091", outer_length_cm: BigDecimal("123"), outer_width_cm: BigDecimal("9"), outer_height_cm: BigDecimal("7"), outer_box_weight_kg: BigDecimal("9"), outer_box_pcs: 1 },
    { source_row: 114, sku_code: "ZJ092", outer_length_cm: BigDecimal("60"), outer_width_cm: BigDecimal("10"), outer_height_cm: BigDecimal("10"), outer_box_weight_kg: BigDecimal("4"), outer_box_pcs: 1 },
    { source_row: 115, sku_code: "ZJ093", outer_length_cm: BigDecimal("56"), outer_width_cm: BigDecimal("9.5"), outer_height_cm: BigDecimal("5"), outer_box_weight_kg: BigDecimal("3.5"), outer_box_pcs: 1 },
    { source_row: 116, sku_code: "MPJ001-DG", inner_box_weight_kg: BigDecimal("2.2"), outer_length_cm: BigDecimal("42"), outer_width_cm: BigDecimal("12"), outer_height_cm: BigDecimal("42"), outer_box_weight_kg: BigDecimal("2.6"), outer_box_pcs: 1 },
    { source_row: 117, sku_code: "MPJ001-YL", outer_box_pcs: 1 },
    { source_row: 118, sku_code: "MPJ002", inner_box_weight_kg: BigDecimal("1.258"), outer_length_cm: BigDecimal("36"), outer_width_cm: BigDecimal("10"), outer_height_cm: BigDecimal("20"), outer_box_weight_kg: BigDecimal("1.6"), outer_box_pcs: 1 },
    { source_row: 119, sku_code: "MPJ003-LG", inner_box_weight_kg: BigDecimal("3.5"), outer_length_cm: BigDecimal("40"), outer_width_cm: BigDecimal("16"), outer_height_cm: BigDecimal("32"), outer_box_weight_kg: BigDecimal("4"), outer_box_pcs: 1 },
    { source_row: 120, sku_code: "MPJ003-YL", outer_box_pcs: 1 },
    { source_row: 121, sku_code: "MPJ004-DG", inner_box_weight_kg: BigDecimal("9.8"), outer_length_cm: BigDecimal("56"), outer_width_cm: BigDecimal("20"), outer_height_cm: BigDecimal("40"), outer_box_weight_kg: BigDecimal("10.5"), outer_box_pcs: 1 },
    { source_row: 122, sku_code: "MPJ004-YL", outer_box_pcs: 1 },
    { source_row: 123, sku_code: "LDD010" },
    { source_row: 124, sku_code: "LDD009", outer_length_cm: BigDecimal("53"), outer_width_cm: BigDecimal("45"), outer_height_cm: BigDecimal("34.5"), outer_box_pcs: 3 },
    { source_row: 125, sku_code: "LDD008" },
    { source_row: 126, sku_code: "LDD007", outer_length_cm: BigDecimal("60.5"), outer_width_cm: BigDecimal("45"), outer_height_cm: BigDecimal("34.5"), outer_box_pcs: 3 },
    { source_row: 127, sku_code: "LDD006" },
    { source_row: 128, sku_code: "CYQ95-WT", inner_box_weight_kg: BigDecimal("0.35"), outer_length_cm: BigDecimal("48.5"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("51"), outer_box_weight_kg: BigDecimal("14"), outer_box_pcs: 40 },
    { source_row: 129, sku_code: "CYQ95-BK", inner_box_weight_kg: BigDecimal("0.35"), outer_length_cm: BigDecimal("48.5"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("51"), outer_box_weight_kg: BigDecimal("14"), outer_box_pcs: 40 },
    { source_row: 130, sku_code: "XC001", inner_box_weight_kg: BigDecimal("0.45"), outer_length_cm: BigDecimal("51"), outer_width_cm: BigDecimal("49"), outer_height_cm: BigDecimal("53"), outer_box_weight_kg: BigDecimal("17"), outer_box_pcs: 36 },
    { source_row: 131, sku_code: "XC002", inner_box_weight_kg: BigDecimal("0.3"), outer_length_cm: BigDecimal("54"), outer_width_cm: BigDecimal("47"), outer_height_cm: BigDecimal("67.5"), outer_box_weight_kg: BigDecimal("16.3"), outer_box_pcs: 48 },
    { source_row: 132, sku_code: "XC003", inner_box_weight_kg: BigDecimal("0.55"), outer_length_cm: BigDecimal("56"), outer_width_cm: BigDecimal("48"), outer_height_cm: BigDecimal("70"), outer_box_weight_kg: BigDecimal("13.2"), outer_box_pcs: 24 },
    { source_row: 133, sku_code: "XC004", inner_box_weight_kg: BigDecimal("0.55"), outer_length_cm: BigDecimal("52"), outer_width_cm: BigDecimal("46"), outer_height_cm: BigDecimal("61"), outer_box_weight_kg: BigDecimal("20.05"), outer_box_pcs: 36 },
    { source_row: 134, sku_code: "XC005", inner_box_weight_kg: BigDecimal("0.45"), outer_length_cm: BigDecimal("52"), outer_width_cm: BigDecimal("47"), outer_height_cm: BigDecimal("61"), outer_box_weight_kg: BigDecimal("16.55"), outer_box_pcs: 36 },
    { source_row: 135, sku_code: "XC006", inner_box_weight_kg: BigDecimal("0.55"), outer_length_cm: BigDecimal("52"), outer_width_cm: BigDecimal("47"), outer_height_cm: BigDecimal("61"), outer_box_weight_kg: BigDecimal("18.15"), outer_box_pcs: 36 },
    { source_row: 136, sku_code: "XC051", inner_box_weight_kg: BigDecimal("0.35"), outer_length_cm: BigDecimal("52"), outer_width_cm: BigDecimal("47"), outer_height_cm: BigDecimal("67"), outer_box_weight_kg: BigDecimal("20.5"), outer_box_pcs: 36 },
    { source_row: 137, sku_code: "XC052", inner_box_weight_kg: BigDecimal("1.05"), outer_length_cm: BigDecimal("52"), outer_width_cm: BigDecimal("47"), outer_height_cm: BigDecimal("61"), outer_box_weight_kg: BigDecimal("36.45"), outer_box_pcs: 36 },
    { source_row: 138, sku_code: "XC053", inner_box_weight_kg: BigDecimal("0.4"), outer_length_cm: BigDecimal("52"), outer_width_cm: BigDecimal("46"), outer_height_cm: BigDecimal("66"), outer_box_weight_kg: BigDecimal("19.05"), outer_box_pcs: 48 },
    { source_row: 139, sku_code: "XC054", inner_box_weight_kg: BigDecimal("0.55"), outer_length_cm: BigDecimal("52"), outer_width_cm: BigDecimal("47"), outer_height_cm: BigDecimal("60"), outer_box_weight_kg: BigDecimal("20"), outer_box_pcs: 48 },
    { source_row: 140, sku_code: "KJ-204-GD", inner_box_weight_kg: BigDecimal("1.7"), outer_length_cm: BigDecimal("46"), outer_width_cm: BigDecimal("46"), outer_height_cm: BigDecimal("30"), outer_box_weight_kg: BigDecimal("12.5"), outer_box_pcs: 5 },
    { source_row: 141, sku_code: "KJ-204-SV", inner_box_weight_kg: BigDecimal("1.7"), outer_length_cm: BigDecimal("46"), outer_width_cm: BigDecimal("46"), outer_height_cm: BigDecimal("30"), outer_box_weight_kg: BigDecimal("12.5"), outer_box_pcs: 5 },
    { source_row: 142, sku_code: "KJ-204-BK", inner_box_weight_kg: BigDecimal("1.7"), outer_length_cm: BigDecimal("46"), outer_width_cm: BigDecimal("46"), outer_height_cm: BigDecimal("30"), outer_box_weight_kg: BigDecimal("12.5"), outer_box_pcs: 5 },
    { source_row: 143, sku_code: "KJ-212-GD", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("66"), outer_height_cm: BigDecimal("40"), outer_box_pcs: 5 },
    { source_row: 144, sku_code: "KJ-212-SV", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("66"), outer_height_cm: BigDecimal("40"), outer_box_pcs: 5 },
    { source_row: 145, sku_code: "KJ-212-BK", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("66"), outer_height_cm: BigDecimal("40"), outer_box_pcs: 5 },
    { source_row: 146, sku_code: "KJ-213-GD", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("74"), outer_height_cm: BigDecimal("45"), outer_box_pcs: 5 },
    { source_row: 147, sku_code: "KJ-213-SV", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("74"), outer_height_cm: BigDecimal("45"), outer_box_pcs: 5 },
    { source_row: 148, sku_code: "KJ-213-BK", outer_length_cm: BigDecimal("47"), outer_width_cm: BigDecimal("74"), outer_height_cm: BigDecimal("45"), outer_box_pcs: 5 },
    { source_row: 149, sku_code: "KJ-214-GD", outer_length_cm: BigDecimal("46"), outer_width_cm: BigDecimal("46"), outer_height_cm: BigDecimal("40"), outer_box_pcs: 5 },
    { source_row: 150, sku_code: "KJ-214-SV", outer_length_cm: BigDecimal("46"), outer_width_cm: BigDecimal("46"), outer_height_cm: BigDecimal("40"), outer_box_pcs: 5 },
    { source_row: 151, sku_code: "KJ-214-BK", outer_length_cm: BigDecimal("46"), outer_width_cm: BigDecimal("46"), outer_height_cm: BigDecimal("40"), outer_box_pcs: 5 },
    { source_row: 152, sku_code: "ZJ001", inner_box_weight_kg: BigDecimal("1.85"), outer_length_cm: BigDecimal("66"), outer_width_cm: BigDecimal("17"), outer_height_cm: BigDecimal("32"), outer_box_weight_kg: BigDecimal("19.5"), outer_box_pcs: 10 },
    { source_row: 153, sku_code: "ZJ002", inner_box_weight_kg: BigDecimal("3.88"), outer_length_cm: BigDecimal("63"), outer_width_cm: BigDecimal("39"), outer_height_cm: BigDecimal("25"), outer_box_weight_kg: BigDecimal("20.4"), outer_box_pcs: 5 },
    { source_row: 154, sku_code: "ZJ003", inner_box_weight_kg: BigDecimal("10"), outer_length_cm: BigDecimal("143"), outer_width_cm: BigDecimal("36"), outer_height_cm: BigDecimal("8"), outer_box_weight_kg: BigDecimal("10"), outer_box_pcs: 1 },
    { source_row: 155, sku_code: "ZJ004", inner_box_weight_kg: BigDecimal("12"), outer_length_cm: BigDecimal("71"), outer_width_cm: BigDecimal("43"), outer_height_cm: BigDecimal("10"), outer_box_weight_kg: BigDecimal("12"), outer_box_pcs: 1 },
    { source_row: 156, sku_code: "ZJ005", inner_box_weight_kg: BigDecimal("5.5"), outer_length_cm: BigDecimal("110"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("6.5"), outer_box_weight_kg: BigDecimal("5.5"), outer_box_pcs: 1 },
    { source_row: 157, sku_code: "ZJ006", inner_box_weight_kg: BigDecimal("9.55"), outer_length_cm: BigDecimal("86"), outer_width_cm: BigDecimal("52"), outer_height_cm: BigDecimal("10.5"), outer_box_weight_kg: BigDecimal("9.55"), outer_box_pcs: 1 },
    { source_row: 158, sku_code: "ZJ007", inner_box_weight_kg: BigDecimal("1.7"), outer_length_cm: BigDecimal("59"), outer_width_cm: BigDecimal("37"), outer_height_cm: BigDecimal("25"), outer_box_weight_kg: BigDecimal("18"), outer_box_pcs: 10 },
    { source_row: 159, sku_code: "ZJ008", inner_box_weight_kg: BigDecimal("4.2"), outer_length_cm: BigDecimal("73"), outer_width_cm: BigDecimal("36"), outer_height_cm: BigDecimal("25"), outer_box_weight_kg: BigDecimal("4.2"), outer_box_pcs: 5 },
    { source_row: 160, sku_code: "DJ002", inner_box_weight_kg: BigDecimal("58"), outer_length_cm: BigDecimal("136"), outer_width_cm: BigDecimal("57"), outer_height_cm: BigDecimal("17"), outer_box_weight_kg: BigDecimal("60"), outer_box_pcs: 1 },
    { source_row: 161, sku_code: "DJ001", inner_box_weight_kg: BigDecimal("58"), outer_length_cm: BigDecimal("136"), outer_width_cm: BigDecimal("57"), outer_height_cm: BigDecimal("17"), outer_box_weight_kg: BigDecimal("60"), outer_box_pcs: 1 },
    { source_row: 162, sku_code: "KJ-218-GD", outer_box_pcs: 5 },
    { source_row: 163, sku_code: "KJ-218-GY", outer_length_cm: BigDecimal("48"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("57"), outer_box_pcs: 5 },
    { source_row: 164, sku_code: "KJ-226-GD", inner_box_weight_kg: BigDecimal("1.3"), outer_length_cm: BigDecimal("79"), outer_width_cm: BigDecimal("36"), outer_height_cm: BigDecimal("38"), outer_box_weight_kg: BigDecimal("15"), outer_box_pcs: 10 },
    { source_row: 165, sku_code: "KJ-226-SV" },
    { source_row: 166, sku_code: "KJ-226-GY" },
    { source_row: 167, sku_code: "KJ-226-RG" },
    { source_row: 168, sku_code: "KJ-226-BK" },
    { source_row: 169, sku_code: "HZX001", inner_box_weight_kg: BigDecimal("6"), outer_length_cm: BigDecimal("78"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("26"), outer_box_weight_kg: BigDecimal("7"), outer_box_pcs: 1 },
    { source_row: 170, sku_code: "HZX002", inner_box_weight_kg: BigDecimal("6"), outer_length_cm: BigDecimal("78"), outer_width_cm: BigDecimal("26"), outer_height_cm: BigDecimal("26"), outer_box_weight_kg: BigDecimal("7"), outer_box_pcs: 1 },
    { source_row: 171, sku_code: "CZY001", inner_box_weight_kg: BigDecimal("0.05"), outer_length_cm: BigDecimal("44.5"), outer_width_cm: BigDecimal("34"), outer_height_cm: BigDecimal("36.5"), outer_box_weight_kg: BigDecimal("10.7"), outer_box_pcs: 200 },
    { source_row: 172, sku_code: "KJ-207-GD", outer_length_cm: BigDecimal("44"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("66"), outer_box_pcs: 5 },
    { source_row: 173, sku_code: "KJ-207-WT" },
    { source_row: 174, sku_code: "KJ-207-GY" },
    { source_row: 175, sku_code: "LDD001-BK", inner_box_weight_kg: BigDecimal("5.8"), outer_length_cm: BigDecimal("42.5"), outer_width_cm: BigDecimal("33.5"), outer_height_cm: BigDecimal("44"), outer_box_weight_kg: BigDecimal("37.9"), outer_box_pcs: 3 },
    { source_row: 176, sku_code: "LDD001-GD", inner_box_weight_kg: BigDecimal("5.8"), outer_length_cm: BigDecimal("67"), outer_width_cm: BigDecimal("49"), outer_height_cm: BigDecimal("40.5"), outer_box_weight_kg: BigDecimal("37.9"), outer_box_pcs: 3 },
    { source_row: 177, sku_code: "LDD002", inner_box_weight_kg: BigDecimal("5.4"), outer_length_cm: BigDecimal("52.5"), outer_width_cm: BigDecimal("44.5"), outer_height_cm: BigDecimal("34.5"), outer_box_weight_kg: BigDecimal("17.2"), outer_box_pcs: 3 },
    { source_row: 178, sku_code: "LDD002-BK", inner_box_weight_kg: BigDecimal("5.4"), outer_length_cm: BigDecimal("68"), outer_width_cm: BigDecimal("56.5"), outer_height_cm: BigDecimal("45"), outer_box_weight_kg: BigDecimal("34.5"), outer_box_pcs: 3 },
    { source_row: 179, sku_code: "LDD003", inner_box_weight_kg: BigDecimal("4.9"), outer_length_cm: BigDecimal("61"), outer_width_cm: BigDecimal("44.5"), outer_height_cm: BigDecimal("40.5"), outer_box_weight_kg: BigDecimal("30.7"), outer_box_pcs: 6 },
    { source_row: 180, sku_code: "LDD004", inner_box_weight_kg: BigDecimal("5.4"), outer_length_cm: BigDecimal("44.5"), outer_width_cm: BigDecimal("35.5"), outer_height_cm: BigDecimal("63"), outer_box_weight_kg: BigDecimal("16.9"), outer_box_pcs: 3 },
    { source_row: 181, sku_code: "LDD005", inner_box_weight_kg: BigDecimal("4.9"), outer_length_cm: BigDecimal("44.5"), outer_width_cm: BigDecimal("35.5"), outer_height_cm: BigDecimal("51"), outer_box_weight_kg: BigDecimal("15.6"), outer_box_pcs: 3 },
    { source_row: 182, sku_code: "CYQ97-BK", inner_box_weight_kg: BigDecimal("0.35"), outer_length_cm: BigDecimal("48.5"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("51"), outer_box_weight_kg: BigDecimal("14"), outer_box_pcs: 40 },
    { source_row: 183, sku_code: "CYQ97-WT" },
    { source_row: 184, sku_code: "CYQ97-PK", inner_box_weight_kg: BigDecimal("0.35"), outer_length_cm: BigDecimal("48.5"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("51"), outer_box_weight_kg: BigDecimal("14"), outer_box_pcs: 40 },
    { source_row: 185, sku_code: "CYQ97-GN", inner_box_weight_kg: BigDecimal("0.35"), outer_length_cm: BigDecimal("48.5"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("51"), outer_box_weight_kg: BigDecimal("14"), outer_box_pcs: 40 },
    { source_row: 186, sku_code: "CYQ97-BL", inner_box_weight_kg: BigDecimal("0.35"), outer_length_cm: BigDecimal("48.5"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("51"), outer_box_weight_kg: BigDecimal("14"), outer_box_pcs: 40 },
    { source_row: 187, sku_code: "KJ-217-WT", inner_box_weight_kg: BigDecimal("3.3"), outer_length_cm: BigDecimal("54"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("88"), outer_box_weight_kg: BigDecimal("17.5"), outer_box_pcs: 5 },
    { source_row: 188, sku_code: "KJ-217-GD", inner_box_weight_kg: BigDecimal("3.3"), outer_length_cm: BigDecimal("54"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("88"), outer_box_weight_kg: BigDecimal("17.5"), outer_box_pcs: 5 },
    { source_row: 189, sku_code: "KJ-217-GY", inner_box_weight_kg: BigDecimal("3.3"), outer_length_cm: BigDecimal("54"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("88"), outer_box_weight_kg: BigDecimal("17.5"), outer_box_pcs: 5 },
    { source_row: 190, sku_code: "KJ-217-BK", inner_box_weight_kg: BigDecimal("3.2"), outer_length_cm: BigDecimal("54"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("83"), outer_box_weight_kg: BigDecimal("17"), outer_box_pcs: 5 },
    { source_row: 191, sku_code: "KJ-228-WT", inner_box_weight_kg: BigDecimal("3.4"), outer_length_cm: BigDecimal("54"), outer_width_cm: BigDecimal("30"), outer_height_cm: BigDecimal("81"), outer_box_weight_kg: BigDecimal("17.9"), outer_box_pcs: 5 },
    { source_row: 192, sku_code: "KJ-228-BK" },
    { source_row: 193, sku_code: "KJ-228-SV" },
    { source_row: 194, sku_code: "XCQ707", inner_box_weight_kg: BigDecimal("3.2"), outer_length_cm: BigDecimal("60.5"), outer_width_cm: BigDecimal("46.5"), outer_height_cm: BigDecimal("59"), outer_box_pcs: 6 },
    { source_row: 195, sku_code: "JXZ-GREY-01", inner_box_weight_kg: BigDecimal("1.3"), outer_length_cm: BigDecimal("66"), outer_width_cm: BigDecimal("50"), outer_height_cm: BigDecimal("38"), outer_box_weight_kg: BigDecimal("16.8"), outer_box_pcs: 12 },
    { source_row: 196, sku_code: "JXZ-WHITE-02", inner_box_weight_kg: BigDecimal("1.25"), outer_length_cm: BigDecimal("66"), outer_width_cm: BigDecimal("50"), outer_height_cm: BigDecimal("38"), outer_box_weight_kg: BigDecimal("16.8"), outer_box_pcs: 12 },
  ].freeze

  Result = Struct.new(:updated, :unchanged, :skipped, keyword_init: true)

  def initialize(env: ENV, stdout: $stdout)
    @stdout = stdout
    @dry_run = !ActiveModel::Type::Boolean.new.cast(env.fetch("APPLY", false))
    @sku_filter = parse_sku_codes(env["SKU_CODES"])
  end

  def call
    result = Result.new(updated: 0, unchanged: 0, skipped: 0)

    stdout.puts "NPD SKU dimensions import"
    stdout.puts "Source: embedded IMPORT_ROWS"
    stdout.puts "Dry run: #{dry_run ? "yes" : "no"}"
    stdout.puts "SKU filter: #{sku_filter.any? ? sku_filter.join(", ") : "all"}"
    stdout.puts "Rows embedded: #{IMPORT_ROWS.size}"

    ApplicationRecord.transaction do
      IMPORT_ROWS.each { |row| import_row(row, result) }

      raise ActiveRecord::Rollback if dry_run
    end

    stdout.puts "Updated: #{result.updated}"
    stdout.puts "Unchanged: #{result.unchanged}"
    stdout.puts "Skipped: #{result.skipped}"
    stdout.puts "DRY_RUN=1, no data changed. Set APPLY=1 to write." if dry_run

    result
  end

  private

  attr_reader :stdout, :dry_run, :sku_filter

  def import_row(row, result)
    sku_code = normalize_sku(row.fetch(:sku_code))
    return if sku_filter.any? && !sku_filter.include?(sku_code)

    sku = Ec::Sku.find_by(sku_code: sku_code)
    unless sku
      log_skip(row, "SKU not found: #{sku_code}")
      result.skipped += 1
      return
    end

    attributes = row.except(:source_row, :sku_code)
    if attributes.empty?
      log_skip(row, "no valid dimension fields for #{sku_code}")
      result.skipped += 1
      return
    end

    dimension = Ec::SkuDimension.find_or_initialize_by(sku_code: sku_code)
    dimension.assign_attributes(attributes)

    if dimension.changed?
      stdout.puts "#{dry_run ? "DRY" : "UPDATE"} #{sku_code}: #{change_summary(dimension)}"
      dimension.save! unless dry_run
      result.updated += 1
    else
      stdout.puts "UNCHANGED #{sku_code}: #{attributes.inspect}"
      result.unchanged += 1
    end
  end

  def change_summary(record)
    record.changes.transform_values { |before, after| "#{before || "-"} -> #{after}" }.inspect
  end

  def log_skip(row, reason)
    stdout.puts "SKIP row #{row[:source_row]} #{normalize_sku(row[:sku_code]).presence || "-"}: #{reason}"
  end

  def parse_sku_codes(value)
    value.to_s.split(",").map { |sku| normalize_sku(sku) }.reject(&:blank?).uniq
  end

  def normalize_sku(value)
    value.to_s.strip.upcase
  end
end

unless ENV["SKIP_NPD_SKU_DIMENSIONS_IMPORT_AUTORUN"] == "1"
  NpdSkuDimensionsImport.new.call
end
