''' Cambridge Workshop '''
''' November 2013 '''
''' Daniel Murrell and Isidro Cortes '''
''' QSPR example with camb '''

library(camb)
library(ggplot2)
library(doMC)

#########################################
# Standardise molecules
#########################################

StandardiseMolecules(structures.file="solubility_2007_ref2.sdf", 
                     standardised.file="standardised.sdf", 
                     removed.file="removed.sdf",
                     output = "properties.csv",
                     remove.inorganic=TRUE, 
                     fluorine.limit=3, 
                     chlorine.limit=3, 
                     bromine.limit=3, 
                     iodine.limit=3, 
                     min.mass.limit=20, 
                     max.mass.limit=900)

#########################################
# Calculate descriptors for the molecules
#########################################

descriptors <- GeneratePadelDescriptors(standardised.file = "standardised.sdf", types=c("2D"), threads = 1)
descriptors <- RemoveStandardisedPrefix(descriptors)
saveRDS(descriptors, file="descriptors.rds")
descriptors <- readRDS("descriptors.rds")
head(descriptors)

#########################################
# Target Visualization
#########################################

# Having a look at the response variable
properties <- read.csv("properties.csv")
head(properties)
properties <- properties[properties$Kept==1, ]
targets <- data.frame(Name = properties$Name, target = properties$EXPT)
head(targets)
p <- DensityResponse(targets$target)
p + labs(title="LogS target value distribution")

#########################################
# Merge the target values together with the descriptors
#########################################

all <- merge(x=targets, y=descriptors, by="Name")
# check the number of rows are the same
dim(all)
dim(targets)
dim(descriptors)
ids <- all$Name
x <- all[,3:ncol(all)]
y <- all$target

#########################################
# Replace infinite values with NA and impute the NAs
#########################################
x.finite <- ReplaceInfinitesWithNA(x)
x.imputed <- x.finite
x.imputed[which(is.na(x.imputed), arr.ind=TRUE)] <- 0
#x.imputed <- ImputeFeatures(x.finite)

#########################################
# Split the dataset into a training and holdout set
#########################################
dataset <- SplitSet(ids, x.imputed, y, percentage=20)

#########################################
# Remove the descriptors that are highly correlated or have low variance 
#########################################
dataset <- RemoveNearZeroVarianceFeatures(dataset)
dataset <- RemoveHighlyCorrelatedFeatures(dataset)

#########################################
# Preprocess the data (center and scale are the defaults used here)
#########################################
dataset <- PreProcess(dataset)

#########################################
# Generate a 5 folds for cross validation setup
# and save the data that is prepared for model training
#########################################
dataset <- GetCVTrainControl(dataset)
saveRDS(dataset, file="dataset.rds")

#########################################
# Model training
#########################################
registerDoMC(cores=1)

method <- "rf"
tune.grid <- expand.grid(.mtry = seq(5,100,5))
model <- train(dataset$x.train, dataset$y.train, method, tuneGrid=tune.grid, trControl=dataset$trControl)
saveRDS(model, file=paste(method,".rds",sep=""))

method <- "svmRadial"
tune.grid <- expand.grid(.sigma = expGrid(-8, 4, 2, 2), .C = c(0.0001, 0.001, 0.01, 0.1, 1, 10, 100))
model <- train(dataset$x.train, dataset$y.train, method, tuneGrid=tune.grid, trControl=dataset$trControl)
saveRDS(model, file=paste(method,".rds",sep=""))


method <- "gbm"
tune.grid <- expand.grid(.n.trees=c(500,1000), .interaction.depth=c(25), .shrinkage = c(0.04, 0.08, 0.16))
model <- train(dataset$x.train, dataset$y.train, method, tuneGrid=tune.grid, trControl=dataset$trControl)
saveRDS(model, file=paste(method,".rds",sep=""))

#########################################
# Assesing Model Performance
#########################################

# Cross Validation Metrics.
# We assume the metric used for the choice of the best combination of hyperparameters is 'RMSE'.
dataset <- readRDS("dataset.rds")
model <- readRDS("svmRadial.rds")
plot(model, metric = "RMSE")

RMSE_CV(model)
Rsquared_CV(model)

# Predict the values of the hold-out (external) set
holdout.predictions <- as.vector(predict(model, newdata = dataset$x.holdout))
CorrelationPlot(pred=holdout.predictions, obs=dataset$y.holdout)
CorrelationPlot(pred=holdout.predictions, obs=dataset$y.holdout, margin=1, main="LogS Observered vs Predicted", PointSize=1, ColMargin="red")

# Statistics for Model Validation
Validation(holdout.predictions, dataset$y.holdout)