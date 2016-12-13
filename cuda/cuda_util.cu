#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <math.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include <driver_functions.h>
#include "cuda_util.h"

#define THREADSPB 256
#define get_index(i,j) ((jmax+2)*i+j)

double *cudaDevice_u, *cudaDevice_v, *cudaDevice_p, *cudaDevice_f, *cudaDevice_g, *cudaDevice_rhs;
double *cudaDevice_u2, *cudaDevice_v2, *cudaDevice_p2, *cudaDevice_f2, *cudaDevice_g2, *cudaDevice_rhs2;
void cuda_init(int imax, int jmax){
    cudaMalloc(&cudaDevice_u, (imax+2)*(jmax+2) *sizeof(double));
    cudaMalloc(&cudaDevice_v, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_p, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_f, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_g, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_rhs, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_u2, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_v2, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_p2, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_f2, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_g2, (imax+2)*(jmax+2)*sizeof(double));
    cudaMalloc(&cudaDevice_rhs2, (imax+2)*(jmax+2)*sizeof(double));
}

__global__ void setbound_kernel_x(double* cudaDevice_u, double* cudaDevice_v, double* cudaDevice_u2, double* cudaDevice_v2, int imax, int jmax){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int j = idx;
    if(idx>=1&&idx<jmax+1){
        cudaDevice_u2[get_index(j, 0)] = 0;
        cudaDevice_u2[get_index(j, imax)] = 0;
        cudaDevice_v2[get_index(j, 0)] = -cudaDevice_v[get_index(j, 1)];
        cudaDevice_v2[get_index(j, imax+1)] = -cudaDevice_v[get_index(j, imax)];
    }
}

__global__ void setbound_kernel_y(double* cudaDevice_u, double* cudaDevice_v, double* cudaDevice_u2, double* cudaDevice_v2, int imax, int jmax){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int us = 1;
    if(idx>=1&&idx<imax+1){
        cudaDevice_v2[get_index(0, i)] = 0;
        cudaDevice_v2[get_index(jmax, i)] = 0;
        cudaDevice_u2[get_index(0, i)] = -cudaDevice_u[get_index(1, i)];
        cudaDevice_u2[get_index(jmax+1, i)] = 2*us - cudaDevice_u[get_index(jmax, i)];
    }
}

void setbound(double *u,double *v,int imax,int jmax,int wW, int wE,int wN,int wS){
    int nBlocks = (jmax+1 + THREADSPB-1)/THREADSPB;
    setbound_kernel_x<<<nBlocks, THREADSPB>>>(cudaDevice_u, cudaDevice_v, cudaDevice_u2, cudaDevice_v2,imax,jmax);
    nBlocks = (imax+1 + THREADSPB-1)/THREADSPB;
    setbound_kernel_y<<<nBlocks, THREADSPB>>>(cudaDevice_u, cudaDevice_v, cudaDevice_u2, cudaDevice_v2,imax,jmax);
    cudaMemcpy(u, cudaDevice_u2, sizeof(double)*(imax+2)*(jmax+2), cudaMemcpyDeviceToHost);
    cudaMemcpy(v, cudaDevice_v2, sizeof(double)*(imax+2)*(jmax+2), cudaMemcpyDeviceToHost);
    return;
}

__global__ void init_uvp_kernel(double* cudaDevice_u, double* cudaDevice_v, double* cudaDevice_p, int imax, int jmax){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int j = idx/(jmax+2);
    int i = idx%(jmax+2);
    if(idx<(imax+2)*(jmax+2)){
        cudaDevice_u[get_index(j,i)] = UI;
        cudaDevice_v[get_index(j,i)] = VI;
        cudaDevice_p[get_index(j,i)] = PI;
    }
}

void init_uvp(int UI, int VI, int PI){
    int nBlocks = ((jmax+2)*(imax+2) + THREADSPB-1)/THREADSPB;
    init_uvp_kernel<<<nBlocks, THREADSPB>>>(cudaDevice_u, cudaDevice_v, cudaDevice_p, imax,jmax);
}

__global__ void fill_val(double* p, int length, int val){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    p[idx] = val;
}

__global__ void comp_fg_kernel_1(double* cudaDevice_u2, double* cudaDevice_v2, double* cudaDevice_f, double* cudaDevice_g, int imax, int jmax){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int i = idx;
    int j = idx;
    if(j>=1&&j<jmax+1){
        cudaDevice_f[get_index(j,0)] = cudaDevice_u2[get_index(j,0)];
        cudaDevice_f[get_index(j,imax)] = cudaDevice_u2[get_index(j,imax)];
    }
    if(i>=1&&i<imax+1){
        cudaDevice_g[get_index(0,i)] = cudaDevice_v2[get_index(0,i)];
        cudaDevice_g[get_index(jmax,i)] = cudaDevice_v2[get_index(jmax,i)];
    }
}

__global__ void comp_fg_kernel_2(double* cudaDevice_u2, double* cudaDevice_v2, double* cudaDevice_f, double* cudaDevice_g, int imax, int jmax){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int j = idx/(jmax+2);
    int i = idx%(jmax+2);

    if(j>=1&&j<jmax+1){
        if(i>=1&&i<imax){
            a = cudaDevice_u2[get_index(j,i)] + cudaDevice_u2[get_index(j,i+1)];
            b = cudaDevice_u2[get_index(j,i-1)] + cudaDevice_u2[get_index(j,i)];
            c = cudaDevice_u2[get_index(j,i)] - cudaDevice_u2[get_index(j,i+1)];
            d = cudaDevice_u2[get_index(j,i-1)] - cudaDevice_u2[get_index(j,i)];
            e = cudaDevice_u2[get_index(j,i)] + cudaDevice_u2[get_index(j+1,i)];
            ff = cudaDevice_u2[get_index(j-1,i)] + cudaDevice_u2[get_index(j,i)];
            gg = cudaDevice_u2[get_index(j,i)] - cudaDevice_u2[get_index(j+1,i)];
            h = cudaDevice_u2[get_index(j-1,i)] - cudaDevice_u2[get_index(j,i)];
            va = cudaDevice_v2[get_index(j,i)] + cudaDevice_v2[get_index(j,i+1)];
            vb = cudaDevice_v2[get_index(j-1,i)] + cudaDevice_v2[get_index(j-1,i+1)];
            u2x = 1/delx*((a/2)*(a/2)-(b/2)*(b/2))+gamma*1/delx*(abs(a)/2*c/2-abs(b)/2*d/2);
            uvy = 1/dely*(va/2*e/2-vb/2*ff/2)+gamma*1/dely*(abs(va)/2*gg/2-abs(vb)/2*h/2);
            u2x2 = (cudaDevice_u2[get_index(j,i+1)] - 2*cudaDevice_u2[get_index(j,i)] + cudaDevice_u2[get_index(j,i-1)])/(delx*delx);
            u2y2 = (cudaDevice_u2[get_index(j+1,i)] - 2*cudaDevice_u2[get_index(j,i)] + cudaDevice_u2[get_index(j-1,i)])/(dely*dely);
            cudaDevice_f[get_index(j,i)] = cudaDevice_u2[get_index(j,i)] + delt*(1/Re*(u2x2+u2y2)-u2x-uvy+gx);
        }
    }

    if(j>=1&&j<jmax){
        if(i>=1&&i<imax+1){
            a = cudaDevice_v2[get_index(j,i)] + cudaDevice_v2[get_index(j,i+1)];
            b = cudaDevice_v2[get_index(j,i-1)] + cudaDevice_v2[get_index(j,i)];
            c = cudaDevice_v2[get_index(j,i)] - cudaDevice_v2[get_index(j,i+1)];
            d = cudaDevice_v2[get_index(j,i-1)] - cudaDevice_v2[get_index(j,i)];
            e = cudaDevice_v2[get_index(j,i)] + cudaDevice_v2[get_index(j+1,i)];
            ff = cudaDevice_v2[get_index(j-1,i)] + cudaDevice_v2[get_index(j,i)];
            gg = cudaDevice_v2[get_index(j,i)] - cudaDevice_v2[get_index(j+1,i)];
            h = cudaDevice_v2[get_index(j-1,i)] - cudaDevice_v2[get_index(j,i)];
            ua = cudaDevice_u2[get_index(j,i)] + cudaDevice_u2[get_index(j+1,i)];
            ub = cudaDevice_u2[get_index(j,i-1)] + cudaDevice_u2[get_index(j+1,i-1)];
            uvx = 1/delx*(ua/2*a/2-ub/2*b/2)+gamma*1/delx*(abs(ua)/2*c/2-abs(ub)/2*d/2);
            v2y = 1/dely*((e/2)*(e/2)-(ff/2)*(ff/2))+gamma*1/dely*(abs(e)/2*gg/2-abs(ff)/2*h/2);
            v2x2 = (cudaDevice_v2[get_index(j,i+1)] - 2*cudaDevice_v2[get_index(j,i)] + cudaDevice_v2[get_index(j,i-1)])/(delx*delx);
            v2y2 = (cudaDevice_v2[get_index(j+1,i)] - 2*cudaDevice_v2[get_index(j,i)] + cudaDevice_v2[get_index(j-1,i)])/(dely*dely);
            cudaDevice_g[get_index(j,i)] = cudaDevice_v2[get_index(j,i)] + delt*(1/Re*(v2x2+v2y2)-uvx-v2y+gy);
        }
    }
}

void comp_fg(int imax, int jmax,double delt,double delx,double dely,double gx,double gy,double gamma,double Re){
    int nBlocks = ((imax+2)*(jmax+2) + THREADSPB-1)/THREADSPB;
    fill_val<<<nBlocks, THREADSPB>>>(cudaDevice_f, (imax+2)*(jmax+2), 0);
    fill_val<<<nBlocks, THREADSPB>>>(cudaDevice_g, (imax+2)*(jmax+2), 0);

    nBlocks = (max(imax,jmax)+2 + THREADSPB-1)/THREADSPB;
    comp_fg_kernel_1<<<nBlocks, THREADSPB>>>(cudaDevice_u2, cudaDevice_v2, cudaDevice_f, cudaDevice_g, imax, jmax);

    nBlocks = = ((imax+2)*(jmax+2) + THREADSPB-1)/THREADSPB;
    comp_fg_kernel_2<<<nBlocks, THREADSPB>>>(cudaDevice_u2, cudaDevice_v2, cudaDevice_f, cudaDevice_g, imax, jmax);
}

__global__ void comp_rhs_kernel(double* cudaDevice_f2, double* cudaDevice_g2, double* cudaDevice_rhs, int imax, int jmax){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int j = idx/(jmax+2);
    int i = idx%(jmax+2);
    if(j>=1&&j<jmax+1){
        if(i>=1&&i<imax+1){
            int tmp = (cudaDevice_f2[get_index(j,i)]-cudaDevice_f2[get_index(j,i-1)])/delx + (cudaDevice_g2[get_index(j,i)]-cudaDevice_g2[get_index(j-1,i)])/dely;
            cudaDevice_rhs[get_index(j,i)] = 1/delt * tmp;
        }
    }
}

void comp_rhs(int imax, int jmax,double delt,double delx,double dely){
    int nBlocks = ((imax+2)*(jmax+2) + THREADSPB-1)/THREADSPB;
    fill_val<<<nBlocks, THREADSPB>>>(cudaDevice_rhs, (imax+2)*(jmax+2), 0);

    nBlocks = = ((imax+2)*(jmax+2) + THREADSPB-1)/THREADSPB;
    comp_fg_kernel_2<<<nBlocks, THREADSPB>>>(cudaDevice_f2, cudaDevice_g2, cudaDevice_rhs, imax, jmax);
}

double sum_vector(double* device_p, int length){
    thrust::device_ptr<int> d_input = thrust::device_malloc<int>(length);
    thrust::device_ptr<int> d_output = thrust::device_malloc<int>(length);
    cudaMemcpy(d_input.get(), device_p, length * sizeof(double), 
               cudaMemcpyHostToHost);
    thrust::exclusive_scan(d_input, d_input + length, d_output);
    cudaThreadSynchronize();
    double sum = d_output[0];
    thrust::device_free(d_input);
    thrust::device_free(d_output);
    return sum;
}

__global__ poisson_kernel_1(double* cudaDevice_p, double* cudaDevice_p2, double* cudaDevice_r, int imax, int jmax){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int j = idx;
    int i = idx;
    if(j>=1&&j<jmax+1){
        cudaDevice_p[get_index(j,0)] = cudaDevice_p2[get_index(j,1)];
        cudaDevice_p[get_index(j,imax+1)] = cudaDevice_p2[get_index(j,imax)];
    }
    if(i>=1&&i<imax+1){
        cudaDevice_p[get_index(0,i)] = cudaDevice_p2[get_index(1,i)];
        cudaDevice_p[get_index(jmax+1,i)] = cudaDevice_p2[get_index(jmax,i)];
    }
}

__global__ void poisson_kernel_2(double* cudaDevice_r, double* cudaDevice_p, double* cudaDevice_p2, double* cudaDevice_rhs2, int imax, int jmax){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int j = idx/(jmax+2);
    int i = idx%(jmax+2);
    if(j>=1&&j<jmax+1){
        if(i>=1&&i<imax+1){
            eiw=1;eie=1;ejs=1;ejn=1;
            cudaDevice_p[get_index(j,i)] = (1-omg)*cudaDevice_p2[get_index(j,i)]
            +
            omg/((eie+eiw)/(delx*delx)+(ejn+ejs)/(dely*dely)) * (
                (eie*cudaDevice_p2[get_index(j,i+1)]+eiw*cudaDevice_p2[get_index(j,i-1)])/(delx*delx)
                +(ejn*cudaDevice_p2[get_index(j+1,i)]+ejs*cudaDevice_p2[get_index(j-1,i)])/(dely*dely)
                -cudaDevice_rhs2[get_index(j,i)]
            );

            cudaDevice_r[get_index(j,i)] = (
                eie*(cudaDevice_p2[get_index(j,i+1)]-cudaDevice_p2[get_index(j,i)])
                -eiw*(cudaDevice_p2[get_index(j,i)]-cudaDevice_p2[get_index(j,i-1)])
                )/(delx*delx)
            +    (
                ejn*(cudaDevice_p2[get_index(j+1,i)]-cudaDevice_p2[get_index(j,i)])
                -ejs*(cudaDevice_p2[get_index(j,i)]-cudaDevice_p2[get_index(j-1,i)])
                )/(dely*dely)
            - cudaDevice_rhs2[get_index(j,i)];

            cudaDevice_r[get_index(j,i)] = cudaDevice_r[get_index(j,i)]*cudaDevice_r[get_index(j,i)];
        }
    }
}

int poisson(int imax, int jmax,double delx,double dely,double eps,int itermax,double omg){
    int it,j,i,eiw,eie,ejs,ejn;
    double sum;
    double *r;
    double res;
    double* cudaDevice_r;
    cudaMalloc(&cudaDevice_r, (imax+2)*(jmax+2) *sizeof(double));
    for(it=0;it<itermax;it++){
        int nBlocks = ((imax+2)*(jmax+2) + THREADSPB-1)/THREADSPB;
        fill_val<<<nBlocks, THREADSPB>>>(cudaDevice_r, (imax+2)*(jmax+2), 0);

        nBlocks = (max(imax,jmax)+2 + THREADSPB-1)/THREADSPB;
        poisson_kernel_1<<<nBlocks, THREADSPB>>>(cudaDevice_p, cudaDevice_p2, cudaDevice_r, imax, jmax);

        nBlocks = ((imax+2)*(jmax+2) + THREADSPB-1)/THREADSPB;
        poisson_kernel_2<<<nBlocks, THREADSPB>>>(cudaDevice_r, cudaDevice_p, cudaDevice_p2, cudaDevice_rhs2, imax, jmax);

        sum = sum_vector(cudaDevice_r, (imax+2)*(jmax+2));
        res=sqrt(sum/(imax*jmax));
        if(res<eps){
            break;
        }
    }
    cudaFree(cudaDevice_r);
    return it;
}