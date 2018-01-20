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
pkgs <-c("tidyverse", "lubridate", "rgdal", "raster", "gdalUtils")  
# tidyverse - consistent framework for data handling and management
# lubridate - package that simplifies working with dates
# rgdal     - driver for geodata handling
# raster    - package for raster file handling
# gdalUtils - used to read CRS strings from .prj files

# WARNING: for rgdal (and hence raster) to work properly, the GDAL and PROJ.4
# libraries have to be installed (check the README file of the project for 
# instructions).

# check for existence of packages and install if necessary
to_install <- pkgs[!(pkgs %in% installed.packages()[, 1])]
if (length(to_install) > 0)  for (i in seq(to_install)) install.packages(to_install[i])

# load all required packages
for (i in pkgs) require(i, character.only = T)

###############################################################################
######## Load plot coordinates 
###############################################################################
# data are loaded with readr::read_csv() instead of utils::read.csv() to access
# coordinates as tibbles, which print more beatifully
coord <- read_csv("data/csv/Coordinates.csv")
coord

# convert to a SpatialPointsDataFrame 
coord1 <- SpatialPointsDataFrame(coords = coord[,4:3], data = coord, 
                                 proj4string = CRS("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"))
# note coords = coord[,4:3] - order had to be reversed because longitude has 
# to come first

###############################################################################
######## Loading and handling raster files
###############################################################################

# to easily work with the contents of the grids folder, it is useful to be able
# to work with the list.files() function (which lists the contents of a folder)

# get path to a grid with precipitation data using list.files()
# (full.names = TRUE assures that the entire path is returned):
first <- list.files("grids/precipitation/jan", full.names = TRUE)[1]
first # this is the path to the grid with precipitation data for january
      # for the first year in the interval spanned by the DWD data

# it is easy to load the corresponding .asc file with raster()
r1 <- raster(first)
r1 
# unfortunately, the file has the wrong projection (coord. ref. : NA)

# the correct coordinate reference system is stored in grids/projection.prj
# and can be converted to a CRS object with gdalUtils::gdalsrsinfo
proj <- gdalsrsinfo("grids/projection.prj", as.CRS = TRUE)
proj

# the file can be loaded again using the correct CRS information
r2 <- raster(first, crs = proj)
r2 # now the correct coordinate reference system is displayed

# it is possible to plot the raster information, e.g. to inspect if it was
# loaded correctly
plot(r2)

# in order to extract information for the site coordinates, they have to
# be transformed to the same coordinate system 
coord2 <- spTransform(coord1, CRS = proj)

# it is easy to stack a large list of rasters instead of just loading a 
# single raster dataset at a time

# first, list all files in one folder (in this example, precipitation for 
# january)
files <- list.files("grids/precipitation/jan", full.names = TRUE)
head(files)

# load all rasters for january as a stack
jan <- stack(files)
jan 
# the layers in the stacks take their names from the .asc objects
# in the corresponding folder

# for raster stacks, for some reason the coordinate reference has to be
# set manually after loading 
projection(jan) <- proj
jan # now the coord. ref. is correct

# raster stacks can be easily plotted 
plot(jan) # Don't do this when they have lots of layers!

# data for specific coordinates can be extracted from a raster of raster stack 
# with the extract function
extr <- raster::extract(jan, coord2) %>% as.tibble  # the output is converted to tibble

# ...and then be combined with plot information
data <- bind_cols(coord, extr)
data

###############################################################################
######## Batch load and extract DWD data for all months
###############################################################################
# get names of months and path to months
(months     <- list.files("grids/precipitation"))
(monthpaths <- list.files("grids/precipitation", full.names = TRUE))

# create empty list for extracted data
out <- vector(mode = "list", length = length(months))

# loop over all months
for (i in 1:12) {
  # print name of month (to see if loop gets stuck) 
  cat(months[i], "\n")
  # get list of all files for the corresponding month
  files <- list.files(monthpaths[i], full.names = TRUE)
  # stack all rasters in corresponding folder
  temp <- stack(files)
  # set coordinate reference
  projection(temp) <- proj
  # extract data for the plot coordinates and store them together with
  # the original plot level dataset, an indicator of month and the
  # extracted precipitation data
  out[[i]] <- data.frame(coord,                         # plot level data
                         month = months[i],             # indicator for month
                         raster::extract(temp, coord2), # extracted information
                         stringsAsFactors = FALSE       # make sure month is evaluated
                         )                              # as character to avoid warnings
  }                                                     # in later steps
# be careful when working with the ful dataset! for Sebastian's data,
# it took 497.54 seconds

# reshape each table in the list "out" to to longtable, bind rows 
# and rearrange dataset
final_output <- map(out, 
                    function(x) gather(x,
                                       key = "temp",           # name for the column with the column titles
                                       value = "precipitation",# name for the column with the content of the original columns
                                       contains("RSMS")))%>%   # selection criterion (only combine columns that contain the character string "RSMS")
  bind_rows %>% # bind rows of individual data.frames
  separate(temp, into = c("temp1", "monthnum", "year", "temp2")) %>% # separate column with grid names - automatically split at the underscores
  dplyr::select(-temp1, -temp2) %>% # remove unnecessary columns 
                                    # (package for select has to be called
                                    # explicitly because the raster package has a
                                    # select function as well)
  arrange(site, species, monthnum, year) %>%
  as.tibble # convert to tibble format
final_output

###############################################################################
######## Export tidy version of dataset
###############################################################################
# the final output can be exported like this. lubridate::today() is used to 
# automatically add a correct timestamp
write.csv(final_output, 
          file = paste0("output/tidy_precipitation_data_", today(), ".csv"),
          row.names = FALSE)
