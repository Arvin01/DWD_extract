Extract climate information from grids from the DWD Climate Data Center
================

Description
-----------

The Deutsche Wetterdienst (DWD) offers a large amount of freely accessible climate information on its website ([Climate Data Center](https://www.dwd.de/EN/climate_environment/cdc/cdc_node.html)).

The climate information can either be accessed on the level of individual climate stations, or in the form of spatial predictions compressed as ASCII grids (\*.asc.gz files) on a 1 × 1 m² resolution. These grids with climate information are very valuable as they enable to extract climate information for any location in Germany, and thus to obtain site-specific climate information for research sites anywhere in the country.

As this is a common task within [our department](http://plantecology.uni-goettingen.de), the present project attempts to streamline the extraction, processing and aggregation of climate information for a set of plot coordinates. With simple modifications, the same scripts can also be used to extract site-specific information from any other kind of raster dataset (e.g. [WorldClim data](http://www.worldclim.org/) etc.).

Getting the DWD raw data
------------------------

As it would be rather time-consuming to remotely access the DWD datasets from within an R script, the easiest solution is to batch download them all from the FTP server (there are Browser extentions that make this task very easy, such as [DownThemAll](https://addons.mozilla.org/de/firefox/addon/downthemall/) for Mozilla Firefox). *It is also planned to store the datasets in the exchange folder of our department*.

After downloading the files, batch unpack the \*.asc.gz files (can be done by most file archiving software by selecting a list of files, right-clicking and marking "extract here") and delete the original compressed files.

In the present example, we worked with monthly averages of precipitation. We decided to keep the folder structure of the original dataset (grids for all years separated into folders by months), but it would also be possible (and even easier to handle) to store all grids in the same folder (I decided not to do so because this way I can use the script to show how to deal with stacks of rasters of different types that are stored in different folders).

As it would be impossible to store the complete dataset (almost 5 GB) on GitHub, the folder `/grids` contains samples of each 3 grids for all months as an example to show how to deal with this type of datasets.

Setting up an R project
-----------------------

To download a local copy of the present project onto your computer, click on the "clone or download" button in the upper right corner of this GitHub page and choose "Download ZIP"."

![Screenshot of the download menu](figures/screenshot_download.png)

When the file is downloaded, unpack it to your desired project directory. You can then run `example_script.R` to test if everything works on your system. If you are working with [RStudio](https://www.rstudio.com/), you can open the R project file `DWD_extract.Rproj`, which automatically sets the working directory to the project directory. If you are using a different editor, you will have to do this by hand before running the script.

The following sections will explain step by step what is going on in `example_script.R`, and show you how to modify this script to use it for your own purposes.

ADD TREE WITH FOLDER STRUCTURE HERE!

Installation of GDAL and PROJ.4
-------------------------------

As this script is based on the `raster` package, which itself relies on the [Geospatial Data Abstraction Library (GDAL)](http://www.gdal.org/) and (PROJ.4=\[<http://proj4.org/>\], GDAL and PROJ.4 have to be installed before being able to run the script.

In case you are working with Linux, GDAL and PROJ.4 can be installed by opening a shell and entering:

``` bash
sudo apt-get update && sudo apt-get install libgdal-dev libproj-dev
```

Depending on the distribution you are working with, in some cases you might need a newer version of `libgdal-dev` than the version available in the repositories. If you are using Ubuntu and encounter error messages regarding the version of GDAL, you can try to add the [ubuntugis-unstable](https://launchpad.net/~ubuntugis/+archive/ubuntu/ubuntugis-unstable) PPA to your system's repositories (keep in mind that this installs unsupported, experimental packages from an untrusted PPA and might hence be dangerous).

``` bash
sudo add-apt-repository ppa:ubuntugis/ubuntugis-unstable
sudo apt-get update
```

If you are working with Windows, there are several possible ways to install GDAL and PROJ.4, for instance by installing [GISInternals](http://www.gisinternals.com/). Other options are offered on the corresponding websites.

Working with example\_script.R
------------------------------

The next sections describe the different components of `example_script.R`, and show how to run it. Assuming you're working with [RStudio](https://www.rstudio.com/), you can simply open the .Rproj file and `example_script.R`, and then follow the instructions step by step.

### Preparation

First, the packages needed for the analysis have to be loaded. Here's a nice bit of code that checks if all of them are installed, and installs them if they are not available:

``` r
# create list of packages
pkgs <-c("tidyverse", "rgdal", "raster", "gdalUtils")  
# check for existence of packages and install if necessary
to_install<-pkgs[!(pkgs %in% installed.packages()[,1])]
if (length(to_install)>0)  for (i in seq(to_install)) install.packages(to_install[i])
# load all required packages
for (i in pkgs) require(i, character.only = T)
```

The package `tidyverse` is a wrapper around a list of a large amount of very useful packages (e.g. `dplyr`, `purrr`, `ggplot2` and `readr`) that together form a consistent framework for data handling and management. `rgdal` allows R to access the functionalities of the GDAL library, `raster` is a package for efficient raster file handling and `gdalUtils` is used to read CRS strings from .prj files.

### Load plot coordinates

The dataset with the plot coordinates is stored in `/data/csv`. It can be loaded with

``` r
coord <- read_csv("data/csv/Coordinates.csv")
```

    ## Parsed with column specification:
    ## cols(
    ##   site = col_character(),
    ##   species = col_character(),
    ##   latitude = col_double(),
    ##   longitude = col_double()
    ## )

Note that I load the dataset with `readr::read_csv()` instead of `utils::read.csv()`. This loads the coordinates in the `tibble` format, which prints more beatifully than a regular `data.frame`:

``` r
coord
```

    ## # A tibble: 34 x 4
    ##     site species latitude longitude
    ##    <chr>   <chr>    <dbl>     <dbl>
    ##  1    RH      WL 51.59920  10.00921
    ##  2    RH      ES 51.59129  10.00793
    ##  3    RH      SA 51.59129  10.00793
    ##  4    HR      TE 51.59420  10.07873
    ##  5    HR      HB 51.59420  10.07873
    ##  6    KB      SA 51.54180   9.80909
    ##  7    KB      ES 51.54180   9.80909
    ##  8    KB      HB 51.54180   9.80909
    ##  9    LB      TE 51.97858  10.43567
    ## 10    LB      SA 51.97938  10.43071
    ## # ... with 24 more rows

The function `SpatialPointsDataFrame()` can be used to convert `coord` into an object with explicit spatial information:

``` r
coord1 <- SpatialPointsDataFrame(coords = coord[,4:3], data = coord, 
                                 proj4string = CRS("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"))
```

The `proj4string` is a coordinate reference system as provided by the PROJ.4 library (in this case, latitude/longitude as decimal degrees). Note that I specified `coords = coord[,4:3]`: the order of the coordinates had to be reversed because longitude has to come first.
