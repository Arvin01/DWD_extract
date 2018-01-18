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
pkgs <-c("tidyverse", "rgdal", "raster", "gdalUtils")  
# tidyverse - consistent framework for data handling and management
# rgdal     - driver for geodata handling
# raster    - package for raster file handling
# gdalUtils - used to read CRS strings from .prj files

# WARNING: for rgdal (and hence raster) to work properly, the GDAL and PROJ.4
# libraries have to be installed (check the README file of the project for 
# instructions).

# check for existence of packages and install if necessary
to_install<-pkgs[!(pkgs %in% installed.packages()[,1])]
if (length(to_install)>0)  for (i in seq(to_install)) install.packages(to_install[i])

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
######## Batch load and extract dwd data for all months with a loop
###############################################################################
# get names of months and path to months
(months     <- list.files("grids/precipitation"))
(monthpaths <- list.files("grids/precipitation", full.names = TRUE))

# create empty list for extracted data
out <- list()

# loop over all months
for (i in 1:12) {
  # print name of month (to see when loop get stuck) 
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
# be careful when working with the ful dataset! for Sebastian's data,
# it took 497.54 seconds

# reshape output to longtable and bind rows
final_output <- map(out, function(x) gather(x, key = "temp", 
                                            value = "precipitation", 
                                            contains("RSMS")))%>%
  bind_rows %>% # ignore warning about attributes
  as.tibble %>% # convert to tibble
  separate(temp, into = c("temp1", "monthnum", "year", "temp2")) %>% # separate temporary column
  dplyr::select(-temp1, -temp2) # remove unnecessary columns (package for select has to be called
                                # explicitly because the raster package has a select function as well)
  
final_output

###############################################################################
######## Export tidy version of dataset
###############################################################################
write.csv(final_output, 
          file = paste0("output/tidy_precipitation_data_", today(), ".csv"),
          row.names = FALSE)
