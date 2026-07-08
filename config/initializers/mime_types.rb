Mime::Type.register "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx unless Mime::Type.lookup_by_extension(:xlsx)
