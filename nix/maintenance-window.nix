{ config, lib, ... }:

with lib;

let

  cfg = config.maintenanceWindow;

  tzMap = {
    us-west = -8;
    us-central = -6;
    us-east = -5;
    eu-west = 1;
    asia-east = 8;
    asia-northeast = 9;
    asia-southeast = 8;
  };

  firstTZ = fold max (-24) (map (r: tzMap.${r}) config.regions);
  lastTZ = fold min 24 (map (r: tzMap.${r}) config.regions);

  normalizeTime = t: if t < 0 then t+24 else if t >= 24 then t - 24 else t;

in {
  imports = [
    ./regions.nix
  ];

  options = {
    maintenanceWindow = {
      startOfWorkingDay = mkOption {
        type = types.int;
        default = 6;
      };
  
      endOfWorkingDay = mkOption {
        type = types.int;
        default = 21;
      };
  
      firstMaintenanceHour = mkOption {
        type = types.int;
        readOnly = true;
      };
  
      lastMaintenanceHour = mkOption {
        type = types.int;
        readOnly = true;
      };
  
      bestMaintenanceHour = mkOption {
        type = types.int;
        readOnly = true;
      };
    };
  };

  config.maintenanceWindow = {

    # TODO We don't check for conflicts here

    lastMaintenanceHour =
      if firstTZ <= (-24) then cfg.startOfWorkingDay
      else normalizeTime (cfg.startOfWorkingDay - firstTZ);

    firstMaintenanceHour =
      if lastTZ >= 24 then cfg.endOfWorkingDay
      else normalizeTime (cfg.endOfWorkingDay - lastTZ);

    bestMaintenanceHour = normalizeTime (
      cfg.firstMaintenanceHour + (normalizeTime (
        cfg.lastMaintenanceHour - cfg.firstMaintenanceHour
      ) / 2)
    );

  };
}
