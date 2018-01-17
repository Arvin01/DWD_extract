###############################################################################
###############################################################################
######
######    DWD Data
######
######    Script: Roman Link (rlink@gwdg.de)	
######
###############################################################################
###############################################################################

###############################################################################
########  Preparations
###############################################################################

## load packages
# create list of packages
pkgs <-c("tidyverse", "magrittr", "lubridate", "rgdal", "raster")  
# tidyverse - consistent framework for data handling and management
# magrittr  - piping operators (%>%, %<>%, %$% and so on)
# lubridate - simple handling of dates and times
# rgdal     - driver for geodata handling
# raster    - package for raster file handling

# check for existence of packages and install if necessary
to_install<-pkgs[!(pkgs %in% installed.packages()[,1])]
if (length(to_install)>0)  for (i in seq(to_install)) install.packages(to_install[i])

# load all required packages
for (i in pkgs) require(i, character.only = T)

###############################################################################
######## get coordinates 
###############################################################################
coord <- read_csv("data/csv/Coordinates.csv")

coord1 <- SpatialPointsDataFrame(coords = coord[,4:3], data = coord, 
                                 proj4string = CRS(" +proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"))



###############################################################################
######## Load and extract dwd data - first checks
###############################################################################

## check if it is possible to load asc.gz files
# get directory of a random precipitation grid
first <- list.files("grids/precipitation/jan", full.names = TRUE)[1]
first

# try to load with raster
r1 <- raster(first)
r1

# works, but has wrong projection
# get (random) file with correct projection
r2 <- raster("grids/projection.asc")
r2

# get correct projection
proj <- projection(r2)

# test if projections are correct
plot(r2)
points(coord2)

# transform site coordinates to the projection system of the gridded dataset
coord2 <- spTransform(coord1, CRS = proj)

# try to re-load r1 with correct projection
r1 <- raster(first, crs = proj)
r1
# works --> that's how it has to be done in the loop

# list all files for january
files <- list.files("grids/precipitation/jan", full.names = TRUE)

# load all files for january
jan <- stack(files)
# set coordinate reference
projection(jan) <- proj
jan # works

# check if extraction works
system.time(data <- data.frame(coord, month = "jan", extract(jan, coord2)))
data %>% as.tibble

###############################################################################
######## Load and extract dwd data 
###############################################################################
# get names of months and path to months
months     <- list.files("grids/precipitation")
monthpaths <- list.files("grids/precipitation", full.names = TRUE)

# create empty list for extracted data
out <- list()
# loop over all months
system.time({
  for (i in 1:12) {
    # print name of month (to see if loop does get stuck) 
    cat(months[i], "\n")
    # get list of all files for the corresponding month
    files <- list.files(monthpaths[i], full.names = TRUE)
    # stack all rasters in corresponding folder
    temp <- stack(files)
    # set coordinate reference
    projection(temp) <- proj
    # extract data for the plot coordinates from the 
    out[[i]] <- data.frame(coord, month = months[i], extract(temp, coord2))
  }
}) # 497.54 seconds

# reshape output to longtable and bind rows
final_output <- map(out, function(x) gather(x, key = "temp", value = "precipitation", contains("RSMS")))%>%
  bind_rows %>% # ignore warning about attributes
  as.tibble %>% # convert to tibble
  separate(temp, into = c("temp1", "monthnum", "year", "temp2")) %>% # separate temporary column
  dplyr::select(-temp1, -temp2) # remove unnecessary columns (package for select has to be called
                                # explicitly because the raster package has a select function as well)
  
final_output

###############################################################################
######## Export tidy version of dataset
###############################################################################
write.csv(final_output, file = paste0("output/tidy_precipitation_data_", today(), ".csv"), row.names = FALSE)
