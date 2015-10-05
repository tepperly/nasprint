/******
 * Create an SVM model to determine if two QSOs match using machine learning
 *
 */

#ifndef __SVMMODEL_H_LOADED__
#define __SVMMODEL_H_LOADED__

struct svm_model;		/* forward opaque declaration */

struct svm_model *
qso_svm_classifier(void);

/**
 * Return true iff the metrics indicate a match.
 */
int
qso_svm_match(struct svm_model *mod,
	      const double metrics[11]);

#endif /*  __SVMMODEL_H_LOADED__ */
