# approx-optimize-scopf

## Requirements
-   Julia Version 1.9.2
-	InfrastructureModels 0.7.8
-	Ipopt 1.6.0
-	JSON 0.21.4
-	JuMP 1.18.1
-	Memento 1.4.1
-	PowerModels 0.19.10
-	PowerModelsSecurityConstrained 0.10.1

## Repository structure
```
data            // scenario datasets
src
    - prob      // code for building the surrogate problem
    - scripts/c1    
        - solve_time_result     // directory for saving the solving time
```

## Generate base case feasible solutions
```
bash test-stage1-feasible.sh
```

## Test the approx-optimize scopf
```
bash test-approx.sh
```