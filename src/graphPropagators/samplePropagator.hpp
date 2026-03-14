#ifndef SAMPLE_PROPAGATOR_HPP
#define SAMPLE_PROPAGATOR_HPP


#include "../graphChecker.hpp"
#include "../useful.h"

class SamplePropagator : public PartiallyDefinedGraphChecker
{
public:
SamplePropagator()
    {
        this->name = "SamplePropagator";
    }
    void checkProperty(const adjacency_matrix_t &matrix)
    {
        // exclude triangles
        for (size_t i = 0; i < matrix.size(); i++)
            for (size_t j = i + 1; j < matrix.size(); j++)
                for (size_t k = j + 1; k < matrix.size(); k++)
                {
                    if (matrix[i][j] == truth_value_true && matrix[j][k] == truth_value_true && matrix[k][i] == truth_value_true)
                    {
                        forbidden_graph_t f;
                        f.push_back({truth_value_true, {i,j}});
                        f.push_back({truth_value_true, {j,k}});
                        f.push_back({truth_value_true, {k,i}});
                        throw f;
                    }
                }

    }
};

#endif